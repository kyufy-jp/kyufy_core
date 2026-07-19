require "test_helper"

module KyufyCore
  # pgvector integration: a small fixed dataset, deterministic Null embeddings, zero network.
  class RetrieverTest < ActiveSupport::TestCase
    setup do
      @program = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      @document = @program.source_documents.create!(title: "要綱", url: "https://example.jp", body: "本文", fetched_at: Time.now)
      @embedder = KyufyCore.config.embedding_adapter
      @contents = [ "所得の上限に関する要件", "年齢に関する要件", "住所に関する要件" ]
      @contents.each_with_index do |content, i|
        @document.document_chunks.create!(content: content, position: i, embedding: @embedder.embed(content))
      end
    end

    test "nearest_neighbors returns the exact-match chunk first" do
      chunks = Retriever.new.evidence_chunks(program: @program, query: "年齢に関する要件", limit: 3)
      assert_equal "年齢に関する要件", chunks.first.content
    end

    test "search is scoped to the given program" do
      other = build_program(jurisdiction: "prefecture", prefecture_code: "13", name: "別制度")
      other_doc = other.source_documents.create!(title: "要綱2", url: "https://example.jp/2", body: "本文2", fetched_at: Time.now)
      other_doc.document_chunks.create!(content: "所得の上限に関する要件", position: 0, embedding: @embedder.embed("所得の上限に関する要件"))

      chunks = Retriever.new.evidence_chunks(program: @program, query: "所得の上限に関する要件", limit: 5)
      assert chunks.any?
      assert(chunks.all? { |c| c.source_document.program_id == @program.id })
    end

    test "embedding has the configured dimension" do
      assert_equal KyufyCore.config.embedding_dim, @document.document_chunks.first.embedding.size
    end
  end
end
