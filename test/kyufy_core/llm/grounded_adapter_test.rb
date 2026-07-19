require "test_helper"

module KyufyCore
  module LLM
    # Contract tests for the shared grounding logic (batching, JSON parsing, fail-safe),
    # exercised through a stub subclass so no network / key is involved.
    class GroundedAdapterTest < ActiveSupport::TestCase
      FakeProgram = Struct.new(:name)

      class StubGrounded < GroundedAdapter
        attr_reader :seen_user, :seen_system

        def initialize(text)
          @text = text
        end

        def complete_text(system:, user:)
          @seen_system = system
          @seen_user = user
          @text
        end
      end

      def items
        [
          { id: 11, kind: "age", raw_text: "満18歳以上であること。", rule_verdict: :eligible },
          { id: 22, kind: "income", raw_text: "前年の所得が256万円以下であること。", rule_verdict: :ineligible }
        ]
      end

      def program
        FakeProgram.new("テスト給付金")
      end

      test "batched: a single call grounds all requirements, verdicts echo the rule" do
        json = JSON.generate([ { index: 0, explanation: "年齢要件の説明" }, { index: 1, explanation: "所得要件の説明" } ])
        result = StubGrounded.new(json).assess_program(program: program, items: items)

        assert_equal [ 11, 22 ], result.map { |r| r[:id] }
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }, "verdict must come from the rule, not the LLM"
        assert_equal "年齢要件の説明", result[0][:explanation]
        assert_equal "所得要件の説明", result[1][:explanation]
      end

      test "the prompt is batched per program: it names the program and every requirement" do
        adapter = StubGrounded.new("[]")
        adapter.assess_program(program: program, items: items)
        assert_includes adapter.seen_user, "テスト給付金"
        assert_includes adapter.seen_user, "満18歳以上であること。"
        assert_includes adapter.seen_user, "前年の所得が256万円以下であること。"
      end

      test "unparseable output degrades to grounded fallback explanations, verdicts intact" do
        result = StubGrounded.new("すみません、JSONを返せません").assess_program(program: program, items: items)
        assert_equal [ :eligible, :ineligible ], result.map { |r| r[:verdict] }
        assert(result.all? { |r| r[:explanation].to_s.length.positive? })
        assert_includes result[0][:explanation], "満18歳以上であること。"
      end

      test "a missing index in the JSON falls back only for that item" do
        json = JSON.generate([ { index: 0, explanation: "年齢の説明" } ])
        result = StubGrounded.new(json).assess_program(program: program, items: items)
        assert_equal "年齢の説明", result[0][:explanation]
        assert_includes result[1][:explanation], "前年の所得が256万円以下であること。"
      end

      test "an empty response (e.g. a refusal) degrades to fallbacks without raising" do
        result = StubGrounded.new("").assess_program(program: program, items: items)
        assert_equal 2, result.length
        assert(result.all? { |r| r[:explanation].to_s.length.positive? })
      end

      test "plain_language selects the やさしい日本語 system prompt" do
        adapter = StubGrounded.new("[]")
        adapter.assess_program(program: program, items: items, plain_language: true)
        assert_equal GroundedAdapter::PLAIN_LANGUAGE_SYSTEM_PROMPT, adapter.seen_system
        adapter.assess_program(program: program, items: items, plain_language: false)
        assert_equal GroundedAdapter::SYSTEM_PROMPT, adapter.seen_system
      end
    end
  end
end
