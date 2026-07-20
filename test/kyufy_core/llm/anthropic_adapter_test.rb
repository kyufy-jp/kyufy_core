require "test_helper"

module KyufyCore
  module LLM
    # Contract test for the Anthropic adapter with a mocked client — no network, no key.
    class AnthropicAdapterTest < ActiveSupport::TestCase
      FakeProgram = Struct.new(:name)
      FakeBlock = Struct.new(:type, :text)
      FakeMessage = Struct.new(:content, :stop_reason)

      class FakeMessages
        attr_reader :last_args

        def initialize(message)
          @message = message
        end

        def create(**kwargs)
          @last_args = kwargs
          @message
        end
      end

      class FakeAnthropicClient
        attr_reader :messages

        def initialize(message)
          @messages = FakeMessages.new(message)
        end
      end

      def items
        [
          { id: 1, kind: "age", raw_text: "満18歳以上であること。", rule_verdict: :eligible },
          { id: 2, kind: "income", raw_text: "所得256万円以下であること。", rule_verdict: :ineligible }
        ]
      end

      def text_message(text, stop_reason: :end_turn)
        FakeMessage.new([ FakeBlock.new(:text, text) ], stop_reason)
      end

      test "sends a batched Claude request and returns grounded explanations" do
        json = JSON.generate([ { index: 0, explanation: "満18歳以上のため該当。" }, { index: 1, explanation: "所得超過のため非該当。" } ])
        client = FakeAnthropicClient.new(text_message(json))
        adapter = AnthropicAdapter.new(api_key: "test", client: client)

        result = adapter.assess_program(program: FakeProgram.new("テスト給付金"), items: items)

        assert_equal "claude-haiku-4-5", client.messages.last_args[:model]
        assert_equal AnthropicAdapter::MAX_TOKENS, client.messages.last_args[:max_tokens]
        assert_equal 1, client.messages.last_args[:messages].length, "batched into one call"
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }
        assert_equal "満18歳以上のため該当。", result[0][:explanation]
      end

      test "a refusal (stop_reason) degrades to fallback explanations" do
        client = FakeAnthropicClient.new(text_message("", stop_reason: :refusal))
        adapter = AnthropicAdapter.new(api_key: "test", client: client)
        result = adapter.assess_program(program: FakeProgram.new("テスト給付金"), items: items)
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }
        assert(result.all? { |r| r[:explanation].to_s.length.positive? })
      end

      test "the model is configurable" do
        client = FakeAnthropicClient.new(text_message("[]"))
        AnthropicAdapter.new(api_key: "test", model: "claude-haiku-4-5", client: client)
          .assess_program(program: FakeProgram.new("X"), items: items)
        assert_equal "claude-haiku-4-5", client.messages.last_args[:model]
      end

      test "building a real client without a key raises a clear error" do
        adapter = AnthropicAdapter.new(api_key: "", client: nil)
        error = assert_raises(KyufyCore::Error) do
          adapter.send(:client)
        end
        assert_match(/KYUFY_ANTHROPIC_API_KEY/, error.message)
      end
    end
  end
end
