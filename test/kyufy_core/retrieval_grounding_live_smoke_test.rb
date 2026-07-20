require "test_helper"

module KyufyCore
  # LIVE end-to-end smoke test — the ONE path that runs BOTH real adapters through assess():
  # real embeddings (Importer -> pgvector) AND real LLM grounding (Claude). Gated on BOTH
  # ENV["KYUFY_OPENAI_API_KEY"] (embeddings) and ENV["KYUFY_ANTHROPIC_API_KEY"] (grounding);
  # skips cleanly unless both are present, so the suite stays green with zero network otherwise.
  # Keys are read from ENV only and never written to any file.
  #
  # The two sibling live smoke tests each cover a half with the other adapter Null:
  #   - embedding/open_ai_compatible_live_smoke_test.rb — real embeddings, Null LLM
  #   - llm/anthropic_live_smoke_test.rb               — real Claude, Null embeddings
  # This one closes the loop: it proves the real pgvector retrieval and the real grounding work
  # TOGETHER, and specifically exercises the citation back-fill (§6) — a Requirement with no
  # raw_text must be cited from a semantically-retrieved chunk, not from a stored excerpt.
  #
  #   KYUFY_OPENAI_API_KEY=... KYUFY_ANTHROPIC_API_KEY=... \
  #     bin/rails test test/kyufy_core/retrieval_grounding_live_smoke_test.rb
  class RetrievalGroundingLiveSmokeTest < ActiveSupport::TestCase
    # A national program with a document body carrying the income criterion, and an income
    # Requirement with raw_text: nil — so citation_for must fall through to pgvector retrieval.
    DOCUMENT_BODY =
      "本給付金は、前年の所得が256万円以下の世帯を対象とします。所得には給与所得および事業所得を含みます。" \
      "住民税の課税状況にかかわらず、所得要件を満たす方は申請できます。".freeze

    setup do
      unless ENV["KYUFY_OPENAI_API_KEY"].present? && ENV["KYUFY_ANTHROPIC_API_KEY"].present?
        skip "KYUFY_OPENAI_API_KEY and KYUFY_ANTHROPIC_API_KEY must both be set — skipping live retrieval+grounding smoke test"
      end

      KyufyCore.configure do |c|
        c.embedding_adapter = Embedding::OpenAICompatibleAdapter.new
        c.llm_adapter       = LLM::AnthropicAdapter.new
      end

      # Import through the real Importer so every chunk is embedded by the real adapter and
      # persisted into the vector() column — the exact production ingestion path.
      Ingestion::Importer.new.import([ normalized_program ])
    end

    test "real embeddings + real Claude ground a raw_text-less requirement from a retrieved chunk" do
      program = KyufyCore::Program.find_by!(name: "所得要件テスト給付金")

      # 1) The embedding half really ran: chunks carry a persisted vector of the configured width.
      chunk = program.source_documents.first.document_chunks.first
      assert_equal KyufyCore.config.embedding_dim, chunk.embedding.size,
        "the persisted embedding matches the vector() column width"

      # 2) assess() drives retrieval + grounding together.
      result = KyufyCore.assess(
        profile: { residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 }
      )
      assessed = result.program_results.find { |pr| pr.program_name == "所得要件テスト給付金" }
      refute_nil assessed, "the imported program must be assessed"
      assert_equal :eligible, assessed.verdict, "income 864,000 <= 2,560,000 threshold"

      income = assessed.reasons.find { |r| r[:kind] == :income }
      refute_nil income, "an income reason is present"

      # 3) The citation was BACK-FILLED from a real pgvector-retrieved chunk (raw_text was nil),
      #    proving Importer -> embed -> nearest_neighbors -> citation all wired through real models.
      assert_equal :present, income[:citation_status], "retrieval produced a citation"
      assert income[:citation].to_s.strip.length.positive?, "the citation is non-empty"
      assert DOCUMENT_BODY.include?(income[:citation].to_s.strip),
        "the citation is a verbatim excerpt of the retrieved document body, not a stored raw_text"
      assert_includes income[:citation].to_s, "所得", "the retrieved excerpt is the income criterion"

      # 4) The grounding half really ran: Claude produced a non-empty explanation with the URL.
      assert income[:explanation].to_s.strip.length.positive?, "Claude produced an explanation"
      assert_match %r{\Ahttps?://}, income[:source_url].to_s, "the official_url travels with the reason"

      puts "\n--- Live retrieval + grounding (所得要件テスト給付金 => #{assessed.verdict}) ---"
      puts "  引用(retrieved): #{income[:citation]}"
      puts "  説明(Claude):    #{income[:explanation]}"
      puts "  出典:            #{income[:source_url]}"
    end

    private

    def normalized_program
      Ingestion::NormalizedProgram.new(
        name: "所得要件テスト給付金",
        authority: "テスト省",
        jurisdiction: "national",
        category: "給付金",
        target: "individual",
        official_url: "https://example.go.jp/test-income-benefit",
        status: "active",
        source_documents: [
          Ingestion::NormalizedDocument.new(
            title: "所得要件テスト給付金 実施要綱",
            url: "https://example.go.jp/test-income-benefit",
            body: DOCUMENT_BODY
          )
        ],
        requirements: [
          Ingestion::NormalizedRequirement.new(
            kind: "income", operator: "lte", value: { "threshold" => 2_560_000 },
            raw_text: nil,          # <- forces citation_for to fall through to pgvector retrieval
            document_ref: 0
          )
        ]
      )
    end
  end
end
