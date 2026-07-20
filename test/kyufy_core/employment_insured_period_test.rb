require "test_helper"

module KyufyCore
  # 一般教育訓練給付金 needs 雇用保険被保険者 status AND 被保険者期間3年以上（初回1年以上）. The insured
  # period isn't a Profile field, so the engine must NOT hand an employee a loose 該当 — it caps at
  # 要確認 (with a 逆質問) and only rules out the clearly-not-被保険者 self_employed. This mirrors the
  # 住民税非課税 逆質問 pattern (see tax_exempt_test) but for employment.
  class EmploymentInsuredPeriodTest < ActiveSupport::TestCase
    def kyoiku_program
      program = build_program(jurisdiction: "national", name: "一般教育訓練給付金テスト")
      add_requirement(program, kind: "employment", operator: "eq",
                      value: { "measure" => "雇用保険被保険者期間" },
                      raw_text: "雇用保険の被保険者または被保険者であった方（離職者）")
      program
    end

    def employment_reason(employment)
      KyufyCore.assess(profile: { residence: "新宿区", target: "individual", employment: employment })
        .program_results.first.reasons.find { |r| r[:kind] == :employment }
    end

    test "self_employed is 非該当 (clearly not a 雇用保険被保険者)" do
      kyoiku_program
      assert_equal :ineligible, employment_reason("self_employed")[:verdict]
    end

    test "an employee is 要確認, never a loose 該当 (被保険者期間 is unverifiable)" do
      kyoiku_program
      assert_equal :needs_review, employment_reason("employee")[:verdict]
    end

    test "a former employee / unknown employment is 要確認 (被保険者であった方 may still qualify)" do
      kyoiku_program
      assert_equal :needs_review, employment_reason("unemployed")[:verdict]
      assert_equal :needs_review, employment_reason(nil)[:verdict]
    end

    test "the 要確認 verdicts surface the 被保険者期間 逆質問" do
      kyoiku_program
      question = KyufyCore::FOLLOW_UP_QUESTIONS[:employment_insured_period]
      assert_equal question, employment_reason("employee")[:follow_up]
      assert_equal question, employment_reason(nil)[:follow_up]
    end

    test "no 逆質問 on the 非該当 self_employed case" do
      kyoiku_program
      assert_nil employment_reason("self_employed")[:follow_up]
    end

    test "the 教育訓練 seed no longer over-claims 該当 for an employee (now 要確認)" do
      KyufyCore.import_dir
      kyoiku = KyufyCore.assess(
        profile: { residence: "新宿区", target: "individual", employment: "employee" }
      ).program_results.find { |pr| pr.program_name == "一般教育訓練給付金" }
      employment = kyoiku.reasons.find { |r| r[:kind] == :employment }
      assert_equal :needs_review, employment[:verdict], "unverifiable 被保険者期間 caps at 要確認, not 該当"
      assert_equal KyufyCore::FOLLOW_UP_QUESTIONS[:employment_insured_period], employment[:follow_up]
    end
  end
end
