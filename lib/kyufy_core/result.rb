module KyufyCore
  # The assessment result (§7). Enumerable over per-program results. Exposes prefixed IDs
  # only — never raw PKs.
  class Result
    include Enumerable

    attr_reader :program_results

    def initialize(program_results)
      @program_results = program_results
    end

    def each(&) = program_results.each(&)

    def as_json(*) = program_results.map(&:as_json)

    def to_h = { assessments: as_json }

    # One program's verdict + grounded reasons.
    class ProgramResult
      VERDICTS = %i[eligible ineligible needs_review].freeze

      attr_reader :program_id, :program_name, :verdict, :reasons

      def initialize(program_id:, program_name:, verdict:, reasons:)
        @program_id   = program_id
        @program_name = program_name
        @verdict      = verdict
        @reasons      = reasons
      end

      def disclaimer = KyufyCore::DISCLAIMER

      def as_json(*)
        {
          program_id: program_id,
          program_name: program_name,
          verdict: verdict,
          reasons: reasons.map { |r| r.transform_keys(&:to_s) },
          disclaimer: disclaimer
        }.transform_keys(&:to_s)
      end
    end

    # A single grounded reason. `citation` is the quoted 要綱 excerpt; when it cannot be
    # produced, citation is nil, citation_status is :unavailable, and source_url still
    # carries the official URL (the citation_unavailable degradation — §6 fail-safe).
    class Reason
      # `license` is the cited SourceDocument's license (nullable) — attribution travels with the
      # data to the output (§4/§7). Synthesized reasons (no cited document) carry nil.
      def self.build(requirement_id:, kind:, verdict:, explanation:, citation:, source_url:, license: nil)
        {
          requirement_id: requirement_id,
          kind: kind,
          verdict: verdict,
          explanation: explanation,
          citation: citation,
          citation_status: citation.nil? ? :unavailable : :present,
          source_url: source_url,
          license: license
        }
      end
    end
  end
end
