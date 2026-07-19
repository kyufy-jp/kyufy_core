require "test_helper"

module KyufyCore
  # 世帯 (household) modelling: shared residence, 世帯合算所得 (summed income), and
  # household-level assessment.
  class HouseholdTest < ActiveSupport::TestCase
    # A real さいたま 世帯: three members at one address, only the father earning.
    def saitama_family
      [
        { age: 52, residence: "さいたま市中央区", prior_year_income_jpy: 0, employment: "self_employed", target: "individual" },
        { age: 79, residence: "さいたま市中央区", prior_year_income_jpy: 0, employment: "homemaker", target: "individual" },
        { age: 80, residence: "さいたま市中央区", prior_year_income_jpy: 864_000, employment: "part_time", target: "individual" }
      ]
    end

    test "size and 世帯合算所得 aggregate the members" do
      household = Household.new(members: saitama_family)
      assert_equal 3, household.size
      assert_equal 864_000, household.total_income
    end

    test "the representative profile carries shared residence, member count, and summed income" do
      profile = Household.new(members: saitama_family).to_profile
      assert_equal "さいたま市中央区", profile.residence
      assert_equal 3, profile.household_size
      assert_equal 864_000, profile.prior_year_income_jpy
    end

    test "per-member attributes are not household facts (age left nil -> 要確認 downstream)" do
      profile = Household.new(members: saitama_family).to_profile
      assert_nil profile.age
      assert_nil profile.employment
    end

    test "members must share a residence — the 世帯 rule, enforced" do
      mixed = [
        { residence: "新宿区", prior_year_income_jpy: 0 },
        { residence: "さいたま市中央区", prior_year_income_jpy: 0 }
      ]
      error = assert_raises(KyufyCore::Error) { Household.new(members: mixed) }
      assert_match(/share a residence/, error.message)
    end

    test "an empty household is rejected" do
      assert_raises(KyufyCore::Error) { Household.new(members: []) }
    end

    test "assess_household gates on 世帯合算所得, not any single member's income" do
      KyufyCore.import_yaml
      result = KyufyCore.assess_household(household: { members: saitama_family })
      saitama = result.program_results.find { |pr| pr.program_name == "さいたま市子育て応援給付金" }
      refute_nil saitama, "a さいたま household is assessed for the Saitama program"
      assert_equal :eligible, saitama.verdict, "combined 所得 864,000 is under the 360万円 limit"
    end

    test "assess_household accepts a bare array of members" do
      KyufyCore.import_yaml
      result = KyufyCore.assess_household(household: saitama_family)
      assert result.program_results.any?
    end
  end
end
