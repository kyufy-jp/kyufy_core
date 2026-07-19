require "test_helper"

module KyufyCore
  class RuleCheckTest < ActiveSupport::TestCase
    Req = Struct.new(:kind, :operator, :value, keyword_init: true)

    def evaluate(kind:, operator:, value:, profile:)
      RuleCheck.evaluate(Req.new(kind: kind, operator: operator, value: value), Profile.wrap(profile))
    end

    test "lte boundary values" do
      assert_equal :met,     evaluate(kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }, profile: { prior_year_income_jpy: 2_560_000 })
      assert_equal :met,     evaluate(kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }, profile: { prior_year_income_jpy: 864_000 })
      assert_equal :not_met, evaluate(kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }, profile: { prior_year_income_jpy: 2_560_001 })
    end

    test "gte / gt / lt boundaries" do
      assert_equal :met,     evaluate(kind: "age", operator: "gte", value: { "threshold" => 18 }, profile: { age: 18 })
      assert_equal :not_met, evaluate(kind: "age", operator: "gt",  value: { "threshold" => 18 }, profile: { age: 18 })
      assert_equal :met,     evaluate(kind: "age", operator: "lt",  value: { "threshold" => 65 }, profile: { age: 52 })
    end

    test "eq and in operators" do
      assert_equal :met,     evaluate(kind: "employment", operator: "eq", value: { "eq" => "self_employed" }, profile: { employment: "self_employed" })
      assert_equal :not_met, evaluate(kind: "employment", operator: "eq", value: { "eq" => "employee" }, profile: { employment: "self_employed" })
      assert_equal :met,     evaluate(kind: "employment", operator: "in", value: { "in" => %w[self_employed employee] }, profile: { employment: "employee" })
      assert_equal :not_met, evaluate(kind: "employment", operator: "in", value: { "in" => %w[self_employed] }, profile: { employment: "unemployed" })
    end

    test "missing profile info is undeterminable (fail-safe)" do
      assert_equal :undeterminable, evaluate(kind: "age", operator: "gte", value: { "threshold" => 18 }, profile: { residence: "新宿区" })
    end

    test "income requiring 収入 measure is undeterminable (profile carries only 所得)" do
      assert_equal :undeterminable,
        evaluate(kind: "income", operator: "lte", value: { "threshold" => 2_000_000, "measure" => "収入" }, profile: { prior_year_income_jpy: 864_000 })
    end

    test "exists checks presence" do
      assert_equal :met,     evaluate(kind: "employment", operator: "exists", value: {}, profile: { employment: "self_employed" })
      assert_equal :not_met, evaluate(kind: "employment", operator: "exists", value: {}, profile: {})
    end
  end
end
