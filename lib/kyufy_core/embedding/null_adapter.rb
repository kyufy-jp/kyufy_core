require "digest"

module KyufyCore
  module Embedding
    # Deterministic, no-network embedding adapter for tests and offline runs (§8). The same
    # text always yields the same fixed-dim, L2-normalized vector, derived from a SHA-256 digest
    # of the content — so seeding + pgvector integration tests are fast, free, reproducible, and
    # make zero network calls. Without this the "reproducible test suite" claim would be false.
    class NullAdapter < Adapter
      def embed(text)
        seed = Digest::SHA256.digest(text.to_s)
        bytes = seed.bytes
        raw = Array.new(dim) { |i| (bytes[i % bytes.length] - 127.5) / 127.5 }
        l2_normalize(raw)
      end

      private

      def l2_normalize(vec)
        norm = Math.sqrt(vec.sum { |x| x * x })
        return vec if norm.zero?

        vec.map { |x| x / norm }
      end
    end
  end
end
