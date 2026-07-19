require "test_helper"

module KyufyCore
  module Embedding
    # Contract test for the OpenAI-compatible embedding adapter with a mocked client — no
    # network, no key. Uses a small dim to keep fake vectors readable.
    class OpenAICompatibleAdapterTest < ActiveSupport::TestCase
      class FakeEmbeddingClient
        attr_reader :last_args

        def initialize(vectors)
          @vectors = vectors
        end

        def embed(**kwargs)
          @last_args = kwargs
          @vectors
        end
      end

      test "embed returns a single vector of the configured dimension" do
        client = FakeEmbeddingClient.new([ [ 0.1, 0.2, 0.3, 0.4 ] ])
        adapter = OpenAICompatibleAdapter.new(api_key: "test", model: "opencode-embed", dim: 4, client: client)

        vector = adapter.embed("所得の上限")
        assert_equal [ 0.1, 0.2, 0.3, 0.4 ], vector
        assert_equal "opencode-embed", client.last_args[:model]
        assert_equal 4, client.last_args[:dimensions], "requests the configured dimension"
        assert_equal [ "所得の上限" ], client.last_args[:input]
      end

      test "embed_all batches all texts into one request, preserving order" do
        client = FakeEmbeddingClient.new([ [ 1.0, 0.0, 0.0, 0.0 ], [ 0.0, 1.0, 0.0, 0.0 ] ])
        adapter = OpenAICompatibleAdapter.new(api_key: "test", dim: 4, client: client)

        vectors = adapter.embed_all([ "A", "B" ])
        assert_equal 2, vectors.length
        assert_equal [ "A", "B" ], client.last_args[:input], "one batched request"
      end

      test "request_dimensions: false omits the dimensions param (portability for local servers)" do
        client = FakeEmbeddingClient.new([ [ 0.1, 0.2, 0.3, 0.4 ] ])
        adapter = OpenAICompatibleAdapter.new(api_key: "test", dim: 4, request_dimensions: false, client: client)
        adapter.embed("x")
        assert_nil client.last_args[:dimensions]
      end

      test "embed_all([]) makes no request and returns []" do
        client = FakeEmbeddingClient.new(:should_not_be_called)
        adapter = OpenAICompatibleAdapter.new(api_key: "test", dim: 4, client: client)
        assert_equal [], adapter.embed_all([])
        assert_nil client.last_args
      end

      test "a dimension mismatch raises loudly rather than corrupting the vector column" do
        client = FakeEmbeddingClient.new([ [ 0.1, 0.2 ] ]) # length 2, expected 4
        adapter = OpenAICompatibleAdapter.new(api_key: "test", dim: 4, client: client)
        error = assert_raises(KyufyCore::Error) { adapter.embed("x") }
        assert_match(/dimension mismatch/, error.message)
      end

      test "the HTTP client raises a clear error when no key is set" do
        http = OpenAICompatibleAdapter::HttpClient.new(api_key: "", base_url: "https://example.test/v1")
        error = assert_raises(KyufyCore::Error) do
          http.embed(model: "m", input: [ "x" ], dimensions: 4)
        end
        assert_match(/KYUFY_OPENAI_API_KEY/, error.message)
      end

      test "defaults dim to the configured embedding_dim" do
        adapter = OpenAICompatibleAdapter.new(api_key: "test", client: FakeEmbeddingClient.new([]))
        assert_equal KyufyCore.config.embedding_dim, adapter.dim
      end
    end
  end
end
