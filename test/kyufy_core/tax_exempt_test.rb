require "test_helper"

module KyufyCore
  # Phase 1 of 住民税非課税世帯: answered directly by the Profile (a 逆質問), not computed.
  class TaxExemptTest < ActiveSupport::TestCase
    def suginami_program
      program = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13115")
      add_requirement(program, kind: "income", operator: "lte",
                      value: { "measure" => "住民税非課税" }, raw_text: "住民税非課税世帯であること")
      program
    end

    def income_reason(resident_tax_exempt)
      KyufyCore.assess(profile: { age: 40, residence: "杉並区", target: "individual", resident_tax_exempt: resident_tax_exempt })
        .program_results.first.reasons.find { |r| r[:kind] == :income }
    end

    test "an exempt household clears the 住民税非課税 requirement (該当)" do
      suginami_program
      assert_equal :eligible, income_reason(true)[:verdict]
    end

    test "not-exempt is 要確認, never 非該当 (the requirement may have OR alternatives)" do
      suginami_program
      assert_equal :needs_review, income_reason(false)[:verdict]
    end

    test "unknown status is 要確認 and surfaces the 逆質問" do
      suginami_program
      reason = income_reason(nil)
      assert_equal :needs_review, reason[:verdict]
      assert_equal KyufyCore::FOLLOW_UP_QUESTIONS[:resident_tax_exempt], reason[:follow_up]
    end

    test "no 逆質問 once the field is answered" do
      suginami_program
      assert_nil income_reason(true)[:follow_up]
      assert_nil income_reason(false)[:follow_up]
    end

    test "Household carries 住民税非課税 status into the household assessment" do
      household = Household.new(members: [
        { residence: "杉並区", resident_tax_exempt: true, prior_year_income_jpy: 0 },
        { residence: "杉並区", resident_tax_exempt: true, prior_year_income_jpy: 0 }
      ])
      assert_equal true, household.to_profile.resident_tax_exempt
    end

    test "the 杉並区 seed income requirement now returns a real verdict for an exempt household" do
      KyufyCore.import_dir
      suginami = KyufyCore.assess(
        profile: { age: 40, residence: "杉並区", target: "individual", resident_tax_exempt: true }
      ).program_results.find { |pr| pr.program_name == "杉並区エアコン購入費助成" }
      income = suginami.reasons.find { |r| r[:kind] == :income }
      assert_equal :eligible, income[:verdict], "住民税非課税 clears 杉並区's income requirement (was 要確認)"
    end
  end
end
