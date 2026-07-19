module KyufyCore
  # pgvector search over a program's own 要綱 chunks — used FOR EVIDENCE, never to gate which
  # programs get assessed (§6 step 2). Semantic similarity is lossy; letting it decide candidacy
  # would silently violate the prime directive (§0). `raw_text` on a Requirement is the primary
  # citation; these chunks supplement or back-fill it.
  class Retriever
    def initialize(embedding_adapter: KyufyCore.config.embedding_adapter)
      @embedding_adapter = embedding_adapter
    end

    # Nearest chunks within a single program, ordered by cosine distance.
    # @return [Array<KyufyCore::DocumentChunk>]
    def evidence_chunks(program:, query:, limit: 3)
      return [] if query.to_s.strip.empty?

      vector = @embedding_adapter.embed(query)
      KyufyCore::DocumentChunk
        .joins(:source_document)
        .where(kyufy_core_source_documents: { program_id: program.id })
        .nearest_neighbors(:embedding, vector, distance: "cosine")
        .limit(limit)
        .to_a
    end
  end
end
