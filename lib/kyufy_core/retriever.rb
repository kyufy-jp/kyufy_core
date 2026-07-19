module KyufyCore
  # pgvector search over a program's own 要綱 chunks — used FOR EVIDENCE, never to gate which
  # programs get assessed (§6 step 2). Semantic similarity is lossy; letting it decide candidacy
  # would silently violate the prime directive (§0). `raw_text` on a Requirement is the primary
  # citation; these chunks supplement or back-fill it.
  class Retriever
    def initialize(embedding_adapter: KyufyCore.config.embedding_adapter)
      @embedding_adapter = embedding_adapter
    end

    # Nearest chunks within a single program, ordered by cosine distance. Chunks whose distance
    # exceeds `max_distance` are dropped as too weak to cite (the relevance-rating step from
    # 源内's kb_retrieve_and_rating); nil keeps the nearest regardless. The Assessor treats an
    # empty result as citation_unavailable -> 要確認, so a weak match never becomes a misleading
    # citation.
    # @return [Array<KyufyCore::DocumentChunk>]
    def evidence_chunks(program:, query:, limit: 3, max_distance: KyufyCore.config.evidence_max_distance)
      return [] if query.to_s.strip.empty?

      vector = @embedding_adapter.embed(query)
      chunks = KyufyCore::DocumentChunk
        .joins(:source_document)
        .where(kyufy_core_source_documents: { program_id: program.id })
        .nearest_neighbors(:embedding, vector, distance: "cosine")
        .limit(limit)
        .to_a

      return chunks if max_distance.nil?

      chunks.select { |chunk| chunk.neighbor_distance <= max_distance }
    end
  end
end
