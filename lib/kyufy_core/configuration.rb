module KyufyCore
  # Swappable adapters + embedding dimension (§8). Defaults are the two Null adapters
  # so a fresh install runs green with zero network calls and no credentials.
  class Configuration
    # Different embedding models have different dimensions. This is set once at install
    # time (here + the migration); changing it later means a migration + re-embedding
    # everything. Default 1536 (OpenAI-compatible text-embedding-3-small).
    DEFAULT_EMBEDDING_DIM = 1536

    attr_accessor :llm_adapter, :embedding_adapter, :embedding_dim, :evidence_max_distance

    def initialize
      @embedding_dim     = DEFAULT_EMBEDDING_DIM
      @llm_adapter       = LLM::NullAdapter.new
      @embedding_adapter = Embedding::NullAdapter.new(dim: @embedding_dim)
      # Relevance gate for the pgvector evidence fallback: chunks whose cosine distance to the
      # query exceeds this are dropped rather than cited (mirrors 源内's retrieve-and-rating).
      # nil = off (cite the nearest regardless). Set e.g. 0.5 with a real embedding model.
      @evidence_max_distance = nil
    end
  end
end
