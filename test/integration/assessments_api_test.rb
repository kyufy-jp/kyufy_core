require "test_helper"

module KyufyCore
  # JSON API (§7): POST /kyufy_core/assessments returns the JSON mirror of KyufyCore.assess,
  # prefixed IDs only.
  class AssessmentsApiTest < ActionDispatch::IntegrationTest
    include Engine.routes.url_helpers

    setup do
      @program = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      add_requirement(@program, kind: "age", operator: "gte", value: { "threshold" => 18 })
      add_requirement(@program, kind: "income", operator: "lte", value: { "threshold" => 2_560_000 })
    end

    test "POST /assessments returns grounded JSON with prefixed IDs and disclaimer" do
      post "/kyufy_core/assessments", params: {
        profile: { age: 52, residence: "新宿区", household_size: 3,
                   prior_year_income_jpy: 864_000, employment: "self_employed", target: "individual" },
        categories: %w[給付金 手当 控除]
      }, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assessments = body.fetch("assessments")
      assert assessments.any?

      entry = assessments.find { |a| a["program_id"] == @program.prefix_id }
      refute_nil entry
      assert_match(/\Aprog_/, entry["program_id"])
      assert_equal "eligible", entry["verdict"]
      assert_equal KyufyCore::DISCLAIMER, entry["disclaimer"]
      assert entry["reasons"].any?
      entry["reasons"].each do |reason|
        assert reason.key?("citation")
        assert reason.key?("source_url")
      end
    end

    test "POST /assessments/batch returns one assessment set per profile" do
      post "/kyufy_core/assessments/batch", params: {
        profiles: [
          { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 },
          { age: 40, residence: "さいたま市中央区", target: "individual", prior_year_income_jpy: 864_000 }
        ]
      }, as: :json

      assert_response :success
      results = JSON.parse(response.body).fetch("results")
      assert_equal 2, results.length
      assert(results.all? { |r| r.key?("assessments") })
    end

    test "POST /assessments/household assesses the 世帯 as a unit (income summed)" do
      post "/kyufy_core/assessments/household", params: {
        members: [
          { age: 80, residence: "新宿区", target: "individual", prior_year_income_jpy: 500_000 },
          { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 1_000_000 }
        ]
      }, as: :json

      assert_response :success
      body = JSON.parse(response.body)
      assert body.key?("assessments")
      # The seeded prefecture program has an income requirement (<= 2,560,000). Summed household
      # income is 1,500,000, so the income reason is satisfied (not ineligible).
      income_reasons = body["assessments"].flat_map { |a| a["reasons"] }.select { |r| r["kind"] == "income" }
      assert(income_reasons.none? { |r| r["verdict"] == "ineligible" })
    end

    test "POST /assessments/household with no members returns 422 JSON, not a 500 HTML page" do
      post "/kyufy_core/assessments/household", params: { members: [] }, as: :json

      assert_response :unprocessable_content
      body = JSON.parse(response.body)
      assert body.key?("error")
      assert_match(/at least one member/, body["error"])
    end

    test "POST /assessments/household with members in different municipalities returns 422 JSON" do
      post "/kyufy_core/assessments/household", params: {
        members: [
          { age: 40, residence: "新宿区" },
          { age: 8, residence: "さいたま市中央区" }
        ]
      }, as: :json

      assert_response :unprocessable_content
      body = JSON.parse(response.body)
      assert_match(/share a residence/, body["error"])
    end

    test "plain_language: true yields やさしい日本語 explanations" do
      post "/kyufy_core/assessments", params: {
        profile: { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 },
        plain_language: true
      }, as: :json

      assert_response :success
      explanations = JSON.parse(response.body).fetch("assessments")
        .flat_map { |a| a["reasons"].map { |r| r["explanation"] } }
      assert(explanations.any? { |e| e.to_s.include?("【やさしい日本語】") })
    end

    test "the response never contains a raw program PK as an id" do
      post "/kyufy_core/assessments", params: {
        profile: { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 }
      }, as: :json
      assert_response :success
      refute_match(/"program_id"\s*:\s*"?#{@program.id}"?[,}]/, response.body)
    end
  end
end
