module KyufyCore
  module Embedding
    # Abstract embedding adapter (§8). Turns text into a fixed-dimension vector. The dimension
    # must equal Configuration#embedding_dim (and the vector() column width in the migration).
    class Adapter
      attr_reader :dim

      def initialize(dim:)
        @dim = dim
      end

      # @return [Array<Float>] length == dim
      def embed(text)
        raise NotImplementedError, "#{self.class} must implement #embed"
      end

      # Convenience batch; adapters may override for efficiency.
      def embed_all(texts) = texts.map { |t| embed(t) }
    end
  end
end
