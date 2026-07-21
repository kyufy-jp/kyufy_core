require "test_helper"

module KyufyCore
  module LLM
    # The Null adapter writes the explanations users actually read in offline/demo mode
    # (KYUFY_LLM=null), so its prose is user-facing Japanese — not debug output.
    class NullAdapterTest < ActiveSupport::TestCase
      FakeProgram = Struct.new(:name)

      def program = FakeProgram.new("定額減税（所得税・個人住民税）")

      test "explanations name the requirement kind in Japanese, never the raw English enum" do
        items = KyufyCore::Requirement::KINDS.each_with_index.map do |kind, i|
          { id: i, kind: kind, raw_text: "#{kind}に関する要綱本文。", rule_verdict: :eligible }
        end

        NullAdapter.new.assess_program(program: program, items: items).each_with_index do |result, i|
          kind = KyufyCore::Requirement::KINDS[i]
          label = KyufyCore::Requirement::KIND_LABELS.fetch(kind)
          assert_includes result[:explanation], "#{label}の要件",
            "expected the Japanese label for #{kind}"
          assert_no_match(/#{kind}の要件/, result[:explanation],
            "the raw English kind must not appear in Japanese prose")
        end
      end

      test "the citation-unavailable branch is localized too" do
        item = { id: 1, kind: "income", raw_text: "  ", rule_verdict: :needs_review }

        explanation = NullAdapter.new.assess_program(program: program, items: [ item ]).first[:explanation]

        assert_includes explanation, "（所得）"
        assert_no_match(/income/, explanation)
      end

      test "kind_label falls back to the raw value for an unrecognized kind" do
        assert_equal "所得", KyufyCore::Requirement.kind_label(:income)
        assert_equal "所得", KyufyCore::Requirement.kind_label("income")
        assert_equal "unknown_kind", KyufyCore::Requirement.kind_label("unknown_kind")
      end

      test "every declared kind has a label" do
        assert_equal KyufyCore::Requirement::KINDS.sort,
          KyufyCore::Requirement::KIND_LABELS.keys.sort,
          "KIND_LABELS must cover exactly KINDS"
      end
    end
  end
end
