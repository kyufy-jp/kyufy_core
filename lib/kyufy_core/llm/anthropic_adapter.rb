module KyufyCore
  module LLM
    # Anthropic (Claude) LLM adapter (§8). Grounds explanations via the Claude Messages API;
    # verdicts still come from the rules (§6). Shared batching / parsing / fail-safe live in
    # GroundedAdapter — this class only implements the Claude call.
    #
    # Credentials: reads ENV["KYUFY_ANTHROPIC_API_KEY"] — a DEDICATED key, deliberately separate
    # from ANTHROPIC_API_KEY (which the SDK's credential chain / an OAuth profile would otherwise
    # pick up, e.g. a tooling key). Never hard-code a key.
    #
    # The `anthropic` gem is required lazily so host apps using only the Null adapters don't need
    # it. `model:` is configurable (default claude-opus-4-8; set e.g. "claude-haiku-4-5" to trade
    # explanation quality for cost).
    class AnthropicAdapter < GroundedAdapter
      DEFAULT_MODEL = "claude-opus-4-8".freeze

      def initialize(api_key: ENV["KYUFY_ANTHROPIC_API_KEY"], model: DEFAULT_MODEL, client: nil)
        @api_key = api_key
        @model = model
        @client = client
      end

      private

      def complete_text(system:, user:)
        message = client.messages.create(
          model: @model,
          max_tokens: MAX_TOKENS,
          system_: [ { type: "text", text: system } ],
          messages: [ { role: "user", content: user } ]
        )

        return "" if message.respond_to?(:stop_reason) && message.stop_reason == :refusal

        Array(message.content).select { |block| block.type == :text }.map(&:text).join("\n")
      end

      def client
        @client ||= build_client
      end

      def build_client
        raise KyufyCore::Error, "KYUFY_ANTHROPIC_API_KEY is not set" if @api_key.to_s.empty?

        begin
          require "anthropic"
        rescue LoadError
          raise KyufyCore::Error, "The `anthropic` gem is required for AnthropicAdapter. Add it to your Gemfile."
        end

        Anthropic::Client.new(api_key: @api_key)
      end
    end
  end
end
