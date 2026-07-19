require "test_helper"

module KyufyCore
  module LLM
    # Contract test for the OpenAI-compatible adapter with a mocked client — no network, no key.
    # When the OpenCode key arrives this adapter is a config swap (base_url + api_key + model).
    class OpenAICompatibleAdapterTest < ActiveSupport::TestCase
      FakeProgram = Struct.new(:name)

      class FakeCompletionClient
        attr_reader :last_args

        def initialize(text)
          @text = text
        end

        def complete(**kwargs)
          @last_args = kwargs
          @text
        end
      end

      def items
        [
          { id: 1, kind: "age", raw_text: "満18歳以上であること。", rule_verdict: :eligible },
          { id: 2, kind: "income", raw_text: "所得256万円以下であること。", rule_verdict: :ineligible }
        ]
      end

      test "sends a batched request and returns grounded explanations" do
        json = JSON.generate([ { index: 0, explanation: "年齢要件を満たす。" }, { index: 1, explanation: "所得要件を満たさない。" } ])
        client = FakeCompletionClient.new(json)
        adapter = OpenAICompatibleAdapter.new(api_key: "test", model: "opencode-model", client: client)

        result = adapter.assess_program(program: FakeProgram.new("テスト給付金"), items: items)

        assert_equal "opencode-model", client.last_args[:model]
        assert_includes client.last_args[:user], "テスト給付金"
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }
        assert_equal "年齢要件を満たす。", result[0][:explanation]
      end

      test "an endpoint error degrades to fallback explanations without raising" do
        client = Object.new
        def client.complete(**) = raise KyufyCore::Error, "500 boom"
        adapter = OpenAICompatibleAdapter.new(api_key: "test", client: client)
        result = adapter.assess_program(program: FakeProgram.new("テスト給付金"), items: items)
        assert(result.all? { |r| r[:explanation].to_s.length.positive? })
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }
      end

      test "the HTTP client raises a clear error when no key is set" do
        http = OpenAICompatibleAdapter::HttpClient.new(api_key: "", base_url: "https://example.test/v1")
        error = assert_raises(KyufyCore::Error) do
          http.complete(model: "m", max_tokens: 10, system: "s", user: "u")
        end
        assert_match(/KYUFY_OPENAI_API_KEY/, error.message)
      end
    end
  end
end
