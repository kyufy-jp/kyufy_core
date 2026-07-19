require "test_helper"

module KyufyCore
  # Batch / household assessment: one call, one Result per profile.
  class BatchAssessmentTest < ActiveSupport::TestCase
    setup { KyufyCore.import_yaml }

    # A 世帯 shares an address — members differ by age / income, not residence. Here a 68-year-old
    # and a 40-year-old both live in 新宿区, so they qualify differently for the same 新宿区
    # 高齢者 (age >= 65) program.
    def household
      [
        { age: 68, residence: "新宿区", target: "individual", prior_year_income_jpy: 1_200_000 },
        { age: 40, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 }
      ]
    end

    # Unrelated residents in different municipalities — the "bulk backend job" case, not a 世帯.
    def residents_in_different_cities
      [
        { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 },
        { age: 40, residence: "さいたま市中央区", target: "individual", prior_year_income_jpy: 864_000 }
      ]
    end

    test "each 世帯 member is assessed independently (same residence, different ages)" do
      results = KyufyCore.assess_batch(profiles: household)
      assert_equal 2, results.length

      taxi = "新宿区高齢者福祉タクシー利用助成" # requires age >= 65
      assert_equal :eligible,
        results[0].program_results.find { |pr| pr.program_name == taxi }&.verdict, "the 68-year-old qualifies"
      assert_equal :ineligible,
        results[1].program_results.find { |pr| pr.program_name == taxi }&.verdict, "the 40-year-old does not"
    end

    test "results are returned in input order" do
      results = KyufyCore.assess_batch(profiles: residents_in_different_cities)
      assert_equal 2, results.length
      assert(results.all? { |r| r.is_a?(KyufyCore::Result) })
    end

    test "a bulk job across municipalities keeps profiles isolated" do
      results = KyufyCore.assess_batch(profiles: residents_in_different_cities)
      names0 = results[0].program_results.map(&:program_name)
      names1 = results[1].program_results.map(&:program_name)
      assert_includes names0, "東京都子育て世帯物価高騰支援給付金", "新宿区 resident sees the Tokyo program"
      assert_includes names1, "さいたま市子育て応援給付金", "さいたま resident sees the Saitama program"
      refute_includes names1, "東京都子育て世帯物価高騰支援給付金", "Tokyo programs don't leak across profiles"
    end

    test "assess_batch([]) returns []" do
      assert_equal [], KyufyCore.assess_batch(profiles: [])
    end

    test "plain_language flows through the batch" do
      results = KyufyCore.assess_batch(profiles: [ household.first ], plain_language: true)
      explanations = results.first.program_results.flat_map { |pr| pr.reasons.map { |r| r[:explanation] } }
      assert(explanations.any? { |e| e.to_s.include?("【やさしい日本語】") })
    end
  end
end
