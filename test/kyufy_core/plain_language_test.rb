require "test_helper"

module KyufyCore
  # The やさしい日本語 (easy-Japanese) toggle threaded through assess -> Assessor -> LLM adapter.
  # Uses the Null adapter's deterministic marker so it's verifiable without a network call.
  class PlainLanguageTest < ActiveSupport::TestCase
    def program_with_requirement
      prog = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      prog
    end

    def shinjuku_profile
      { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 }
    end

    def reasons_for(program, plain_language:)
      KyufyCore.assess(profile: shinjuku_profile, plain_language: plain_language)
        .program_results.find { |p| p.program_id == program.prefix_id }
        .reasons
    end

    test "plain_language: true marks explanations as やさしい日本語" do
      program = program_with_requirement
      reasons = reasons_for(program, plain_language: true)
      assert(reasons.any? { |r| r[:explanation].to_s.include?("【やさしい日本語】") })
    end

    test "the default (plain_language: false) does not" do
      program = program_with_requirement
      reasons = reasons_for(program, plain_language: false)
      assert(reasons.none? { |r| r[:explanation].to_s.include?("【やさしい日本語】") })
    end

    test "the toggle does not change verdicts (rules still decide)" do
      program = program_with_requirement
      plain = reasons_for(program, plain_language: true).map { |r| r[:verdict] }
      normal = reasons_for(program, plain_language: false).map { |r| r[:verdict] }
      assert_equal normal, plain
    end
  end
end
