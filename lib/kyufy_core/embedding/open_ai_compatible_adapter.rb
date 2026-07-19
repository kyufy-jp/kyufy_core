require "json"
require "net/http"
require "uri"

module KyufyCore
  module Embedding
    # OpenAI-compatible embedding adapter (§8): calls any `/embeddings` endpoint. The twin of
    # LLM::OpenAICompatibleAdapter — when the OpenCode key arrives, both LLM and embeddings become
    # a config swap (base_url + api_key + model), no code change. Also works for OpenAI itself and
    # local OpenAI-compatible servers.
    #
    # Config from ENV (never hard-code): KYUFY_OPENAI_API_KEY, KYUFY_OPENAI_BASE_URL,
    # KYUFY_OPENAI_EMBEDDING_MODEL. `dim` must match KyufyCore.config.embedding_dim and the
    # vector() column width; it's sent as the request `dimensions` (text-embedding-3-* support
    # truncation) and the returned length is validated so a mismatch fails loudly rather than
    # corrupting the pgvector column.
    class OpenAICompatibleAdapter < Adapter
      DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze
      DEFAULT_MODEL = "text-embedding-3-small".freeze
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 60

      # `request_dimensions` sends OpenAI's `dimensions` truncation param. Real OpenAI
      # text-embedding-3 models honor it; local servers (Ollama, etc.) don't, and some reject
      # unknown fields — set it false there. The returned length is validated against `dim`
      # either way, so a native-dimension mismatch still fails loudly.
      def initialize(api_key: ENV["KYUFY_OPENAI_API_KEY"],
                     base_url: ENV["KYUFY_OPENAI_BASE_URL"] || DEFAULT_BASE_URL,
                     model: ENV["KYUFY_OPENAI_EMBEDDING_MODEL"] || DEFAULT_MODEL,
                     dim: KyufyCore.config.embedding_dim,
                     request_dimensions: true,
                     client: nil)
        super(dim: dim)
        @api_key = api_key
        @base_url = base_url
        @model = model
        @request_dimensions = request_dimensions
        @client = client
      end

      def embed(text)
        embed_all([ text ]).first
      end

      # One request for the whole batch (Importer embeds many chunks) — cheaper than one call
      # per text.
      def embed_all(texts)
        return [] if texts.empty?

        vectors = client.embed(model: @model, input: Array(texts), dimensions: (@request_dimensions ? dim : nil))
        vectors.each do |vector|
          unless vector.is_a?(Array) && vector.length == dim
            raise KyufyCore::Error,
              "embedding dimension mismatch: expected #{dim}, got #{vector&.length.inspect} " \
              "(model #{@model}). Set KyufyCore.config.embedding_dim / the migration to match the model."
          end
        end
        vectors
      end

      private

      def client
        @client ||= HttpClient.new(api_key: @api_key, base_url: @base_url)
      end

      # Minimal Net::HTTP client for the OpenAI embeddings shape. Injectable seam: tests (and
      # OpenCode swaps) can pass any object responding to #embed(model:, input:, dimensions:) ->
      # Array<Array<Float>>.
      class HttpClient
        def initialize(api_key:, base_url:)
          @api_key = api_key
          @base_url = base_url.chomp("/")
        end

        # @return [Array<Array<Float>>] one vector per input, in input order.
        def embed(model:, input:, dimensions:)
          raise KyufyCore::Error, "KYUFY_OPENAI_API_KEY is not set" if @api_key.to_s.empty?

          uri = URI.parse("#{@base_url}/embeddings")
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          body = { model: model, input: input }
          body[:dimensions] = dimensions unless dimensions.nil?
          request.body = JSON.generate(body)

          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request)
          end

          unless response.is_a?(Net::HTTPSuccess)
            raise KyufyCore::Error, "OpenAI-compatible embeddings endpoint returned #{response.code}: #{response.body}"
          end

          data = JSON.parse(response.body).fetch("data", [])
          # The API may return items out of order — sort by index before extracting vectors.
          data.sort_by { |item| item["index"] }.map { |item| item["embedding"] }
        end
      end
    end
  end
end
