require "test_helper"

module KyufyCore
  module Embedding
    # LIVE smoke test — makes real embedding API calls. Gated on ENV["KYUFY_OPENAI_API_KEY"]:
    # runs only when the key is present (OpenCode / OpenAI / a local endpoint), skips cleanly
    # otherwise so the suite stays green with zero network. Key is read from ENV only.
    #
    #   KYUFY_OPENAI_API_KEY=... bin/rails test test/kyufy_core/embedding/open_ai_compatible_live_smoke_test.rb
    class OpenAICompatibleLiveSmokeTest < ActiveSupport::TestCase
      setup do
        skip "KYUFY_OPENAI_API_KEY not set — skipping live embedding smoke test" unless ENV["KYUFY_OPENAI_API_KEY"].present?
        KyufyCore.configure { |c| c.embedding_adapter = OpenAICompatibleAdapter.new } # LLM stays Null
        KyufyCore.import_yaml
      end

      test "real embeddings match the configured dimension and drive pgvector retrieval" do
        program = KyufyCore::Program.find_by!(name: "東京都子育て世帯物価高騰支援給付金")

        chunk = program.source_documents.first.document_chunks.first
        assert_equal KyufyCore.config.embedding_dim, chunk.embedding.size,
          "persisted embedding matches the vector() column width"

        # Semantic retrieval over the program's own 要綱 chunks returns results (not a crash),
        # proving the real embedding adapter wires through Importer + Retriever + pgvector.
        chunks = Retriever.new.evidence_chunks(program: program, query: "所得の要件について", limit: 3)
        assert chunks.any?, "real embedding query returns evidence chunks"
        assert(chunks.all? { |c| c.source_document.program_id == program.id }, "scoped to the program")

        puts "\n--- Live embedding retrieval (query: 所得の要件について) ---"
        chunks.each { |c| puts "  #{c.content}" }
      end
    end
  end
end
