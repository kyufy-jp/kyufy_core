module KyufyCore
  # Swappable adapters + embedding dimension (§8). Defaults are the two Null adapters
  # so a fresh install runs green with zero network calls and no credentials.
  class Configuration
    # Different embedding models have different dimensions. This is set once at install
    # time (here + the migration); changing it later means a migration + re-embedding
    # everything. Default 1536 (OpenAI-compatible text-embedding-3-small).
    DEFAULT_EMBEDDING_DIM = 1536

    # JIS X 0402 codes are 5 digits, and they are Strings because leading zeros are significant.
    CODE_FORMAT = /\A\d{5}\z/

    attr_accessor :llm_adapter, :embedding_adapter, :embedding_dim, :evidence_max_distance

    # Municipalities the packaged JIS table doesn't carry. Geo ships 東京23区 + さいたま市 only
    # (a national table belongs to ingestion), so a program scoped to e.g. 三鷹市 would leave
    # every local resident's address unnormalizable — and the anti-omission rule then caps their
    # whole assessment at 要確認 rather than dropping it. Extending the table is the fix.
    #
    #   KyufyCore.configure do |c|
    #     c.extra_municipalities = { "三鷹市" => "13204", "八王子市" => "13201" }
    #   end
    #
    # Entries here win over the packaged ones, so a wrong or stale code can be corrected without
    # forking. Keep the property the packaged table has: never key a bare ambiguous ward name
    # (中央区, 北区, …) — several cities have one, and a wrong match is worse than a miss
    # (docs/INVARIANTS.md rule 3). Use a disambiguated key like "北区（東京都）".
    attr_reader :extra_municipalities

    def initialize
      @embedding_dim     = DEFAULT_EMBEDDING_DIM
      @llm_adapter       = LLM::NullAdapter.new
      @embedding_adapter = Embedding::NullAdapter.new(dim: @embedding_dim)
      @extra_municipalities = {}.freeze
      # Relevance gate for the pgvector evidence fallback: chunks whose cosine distance to the
      # query exceeds this are dropped rather than cited (mirrors 源内's retrieve-and-rating).
      # nil = off (cite the nearest regardless). Set e.g. 0.5 with a real embedding model.
      @evidence_max_distance = nil
    end

    # Validated at assignment rather than at lookup time: a bad code here would otherwise surface
    # as a silent normalization failure (→ 要確認 for every resident of that municipality), which
    # is exactly the kind of invisible degradation this engine is built to avoid.
    def extra_municipalities=(table)
      @extra_municipalities = self.class.validate_municipalities(table)
    end

    def self.validate_municipalities(table)
      unless table.is_a?(Hash)
        raise ArgumentError, "extra_municipalities must be a Hash of name => JIS code, got #{table.class}"
      end

      table.each do |name, code|
        unless name.is_a?(String) && !name.strip.empty?
          raise ArgumentError,
                "extra_municipalities keys must be non-empty municipality names, got #{name.inspect}"
        end

        unless code.is_a?(String) && code.match?(CODE_FORMAT)
          raise ArgumentError,
                "extra_municipalities[#{name.inspect}] must be a 5-digit JIS X 0402 code as a String, " \
                "got #{code.inspect}. Leading zeros are significant, so quote it: \"01100\", not 01100 " \
                "(which Ruby reads as octal)."
        end
      end

      table.dup.freeze
    end
  end
end
