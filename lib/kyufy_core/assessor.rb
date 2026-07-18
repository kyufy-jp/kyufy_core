require "date"

module KyufyCore
  # The assessment core (§6). Orchestrates: step-0 applicability filter -> rule-check ALL
  # applicable programs -> evidence retrieval -> batched-per-program LLM grounding ->
  # aggregation with explicit precedence -> carve-out verdict cap.
  class Assessor
    RULE_TO_VERDICT = {
      met: :eligible, not_met: :ineligible, undeterminable: :needs_review
    }.freeze

    # Verdict precedence (§6 step 4): any 非該当 > any 要確認 > all 該当.
    PRECEDENCE = { ineligible: 0, needs_review: 1, eligible: 2 }.freeze

    def initialize(profile:, categories: nil,
                   llm_adapter: KyufyCore.config.llm_adapter,
                   retriever: Retriever.new)
      @profile = profile
      @categories = Array(categories).reject { |c| c.to_s.strip.empty? }
      @llm_adapter = llm_adapter
      @retriever = retriever
    end

    def call
      program_results = admissible_programs.map { |program, admission| assess_program(program, admission) }
      Result.new(program_results)
    end

    private

    attr_reader :profile, :categories, :llm_adapter, :retriever

    # Step 0: deterministic applicability filter. Excluding an expired/inactive/out-of-area
    # program here is CORRECT omission; nothing else may exclude a program.
    def admissible_programs
      residence = profile.normalized_residence
      candidates.filter_map do |program|
        admission = geo_admission(program, residence)
        [ program, admission ] unless admission == :none
      end
    end

    def candidates
      today = Date.today
      scope = KyufyCore::Program
        .where(status: "active")
        .where("valid_from IS NULL OR valid_from <= ?", today)
        .where("valid_until IS NULL OR valid_until >= ?", today)
      scope = scope.where(target: profile.target) if profile.target.present?
      scope = scope.where(category: categories) if categories.any?
      scope.includes(requirements: :source_document)
    end

    # :match (assess normally), :ancestor / :carveout_a (assess but cap at 要確認), or :none.
    def geo_admission(program, residence)
      if residence.nil?
        # Carve-out (a): normalization failed -> geography must not exclude. National programs
        # aren't residence-dependent, so they still match; others pass through capped.
        return program.jurisdiction == "national" ? :match : :carveout_a
      end

      Geo.applies(
        residence,
        jurisdiction: program.jurisdiction,
        prefecture_code: program.prefecture_code,
        municipality_code: program.municipality_code
      )
    end

    def capped?(admission)
      admission == :ancestor || admission == :carveout_a
    end

    def assess_program(program, admission)
      requirements = program.requirements.to_a
      evaluations = requirements.map { |req| [ req, RuleCheck.evaluate(req, profile) ] }
      explanations = ground(program, evaluations)

      reasons = evaluations.map do |req, rule|
        build_reason(program, req, rule, explanations[req.id])
      end
      reasons << residence_unverified_reason(program) if capped?(admission)

      Result::ProgramResult.new(
        program_id: program.prefix_id,
        program_name: program.name,
        verdict: aggregate(reasons),
        reasons: reasons
      )
    end

    # Batched per program (§6 step 3): one LLM call grounds all of a program's requirements.
    # Returns { requirement_id => explanation }.
    def ground(program, evaluations)
      items = evaluations.map do |req, rule|
        { id: req.id, kind: req.kind, raw_text: req.raw_text, rule_verdict: RULE_TO_VERDICT.fetch(rule) }
      end
      llm_adapter.assess_program(program: program, items: items)
        .to_h { |entry| [ entry[:id], entry[:explanation] ] }
    end

    def build_reason(program, requirement, rule, explanation)
      citation = citation_for(program, requirement)
      # Rule verdict wins; but a requirement with no citation degrades to 要確認 (§6 fail-safe).
      verdict = citation.nil? ? :needs_review : RULE_TO_VERDICT.fetch(rule)

      Result::Reason.build(
        requirement_id: requirement.prefix_id,
        kind: requirement.kind.to_sym,
        verdict: verdict,
        explanation: explanation,
        citation: citation,
        source_url: program.official_url
      )
    end

    # Primary citation is the requirement's own 要綱 excerpt (raw_text); pgvector chunks
    # back-fill it. nil means no citation could be produced -> citation_unavailable degradation.
    def citation_for(program, requirement)
      excerpt = requirement.raw_text.to_s.strip
      return excerpt unless excerpt.empty?

      chunk = retriever.evidence_chunks(program: program, query: requirement.kind.to_s, limit: 1).first
      chunk&.content&.strip.presence
    end

    # Carve-out cap (§6 step 4): a program admitted via carve-out gets a synthesized residence
    # reason (needs_review). Appending it makes aggregation cap an otherwise-該当 program at
    # 要確認 while leaving a definitive 非該当 intact. citation nil + official_url = the
    # citation_unavailable degradation.
    def residence_unverified_reason(program)
      Result::Reason.build(
        requirement_id: nil,
        kind: :residence,
        verdict: :needs_review,
        explanation: "居住地が制度の対象地域に含まれるか確認が必要です（居住地を特定できませんでした）。",
        citation: nil,
        source_url: program.official_url
      )
    end

    def aggregate(reasons)
      reasons.map { |r| r[:verdict] }.min_by { |v| PRECEDENCE.fetch(v) } || :eligible
    end
  end
end
