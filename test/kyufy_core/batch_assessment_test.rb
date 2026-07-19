require "test_helper"

module KyufyCore
  # Batch / household assessment: one call, one Result per profile.
  class BatchAssessmentTest < ActiveSupport::TestCase
    setup { KyufyCore.import_yaml }

    def household
      [
        { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 },
        { age: 40, residence: "さいたま市中央区", target: "individual", prior_year_income_jpy: 864_000 }
      ]
    end

    test "assess_batch returns one Result per profile, in input order" do
      results = KyufyCore.assess_batch(profiles: household)

      assert_equal 2, results.length
      assert(results.all? { |r| r.is_a?(KyufyCore::Result) })

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
