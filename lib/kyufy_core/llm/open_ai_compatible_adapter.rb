require "json"
require "net/http"
require "uri"

module KyufyCore
  module LLM
    # OpenAI-compatible LLM adapter (§8): talks to any `/chat/completions` endpoint. This is the
    # MVP path for the OpenCode hackathon perk — when its key arrives, OpenCode becomes a config
    # swap (base_url + api_key + model), no code change. Also works for OpenAI itself and local
    # OpenAI-compatible servers.
    #
    # Credentials/config from ENV (never hard-code): KYUFY_OPENAI_API_KEY, KYUFY_OPENAI_BASE_URL,
    # KYUFY_OPENAI_MODEL. Uses Net::HTTP directly (no SDK dependency) so it stays portable across
    # compatible endpoints. Grounding/batching/fail-safe are inherited from GroundedAdapter.
    class OpenAICompatibleAdapter < GroundedAdapter
      DEFAULT_BASE_URL = "https://api.openai.com/v1".freeze
      DEFAULT_MODEL = "gpt-4o-mini".freeze
      OPEN_TIMEOUT = 10
      READ_TIMEOUT = 60

      def initialize(api_key: ENV["KYUFY_OPENAI_API_KEY"],
                     base_url: ENV["KYUFY_OPENAI_BASE_URL"] || DEFAULT_BASE_URL,
                     model: ENV["KYUFY_OPENAI_MODEL"] || DEFAULT_MODEL,
                     client: nil)
        @api_key = api_key
        @base_url = base_url
        @model = model
        @client = client
      end

      private

      def complete_text(system:, user:)
        client.complete(model: @model, max_tokens: MAX_TOKENS, system: system, user: user)
      end

      def client
        @client ||= HttpClient.new(api_key: @api_key, base_url: @base_url)
      end

      # Minimal Net::HTTP client for the OpenAI chat-completions shape. Injectable seam: tests
      # (and OpenCode swaps) can pass any object responding to #complete(model:, max_tokens:,
      # system:, user:) -> String.
      class HttpClient
        def initialize(api_key:, base_url:)
          @api_key = api_key
          @base_url = base_url.chomp("/")
        end

        def complete(model:, max_tokens:, system:, user:)
          raise KyufyCore::Error, "KYUFY_OPENAI_API_KEY is not set" if @api_key.to_s.empty?

          uri = URI.parse("#{@base_url}/chat/completions")
          request = Net::HTTP::Post.new(uri)
          request["Authorization"] = "Bearer #{@api_key}"
          request["Content-Type"] = "application/json"
          request.body = JSON.generate(
            model: model,
            max_tokens: max_tokens,
            messages: [
              { role: "system", content: system },
              { role: "user", content: user }
            ]
          )

          response = Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https",
                                     open_timeout: OPEN_TIMEOUT, read_timeout: READ_TIMEOUT) do |http|
            http.request(request)
          end

          unless response.is_a?(Net::HTTPSuccess)
            raise KyufyCore::Error, "OpenAI-compatible endpoint returned #{response.code}: #{response.body}"
          end

          JSON.parse(response.body).dig("choices", 0, "message", "content").to_s
        end
      end
    end
  end
end
