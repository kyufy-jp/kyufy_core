require "test_helper"

module KyufyCore
  class AssessorTest < ActiveSupport::TestCase
    # A default individual profile living in 新宿区 (東京都).
    def shinjuku_profile(overrides = {})
      { age: 52, residence: "新宿区", household_size: 3,
        prior_year_income_jpy: 864_000, employment: "self_employed", target: "individual" }.merge(overrides)
    end

    def tokyo_pref_program(**opts)
      build_program(jurisdiction: "prefecture", prefecture_code: "13", **opts)
    end

    def verdict_for(program, profile)
      KyufyCore.assess(profile: profile).program_results
        .find { |pr| pr.program_id == program.prefix_id }&.verdict
    end

    # --- aggregation precedence: 非該当 > 要確認 > 該当 ---

    test "all requirements met -> eligible" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      add_requirement(prog, kind: "income", operator: "lte", value: { "threshold" => 2_560_000 })
      assert_equal :eligible, verdict_for(prog, shinjuku_profile)
    end

    test "one not-met requirement disqualifies even if another is undeterminable (非該当 wins)" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }) # not met (income high)
      add_requirement(prog, kind: "household", operator: "gte", value: { "threshold" => 2 })       # undeterminable (no household)
      profile = shinjuku_profile(prior_year_income_jpy: 9_000_000, household_size: nil)
      assert_equal :ineligible, verdict_for(prog, profile)
    end

    test "an undeterminable requirement yields 要確認 (fail-safe) when nothing is not-met" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })        # met
      add_requirement(prog, kind: "household", operator: "gte", value: { "threshold" => 2 })   # undeterminable
      assert_equal :needs_review, verdict_for(prog, shinjuku_profile(household_size: nil))
    end

    # --- applicability filter (step 0) ---

    test "inactive program is excluded" do
      prog = tokyo_pref_program(status: "inactive")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      assert_nil verdict_for(prog, shinjuku_profile)
    end

    test "expired program (valid_until in the past) is excluded" do
      prog = tokyo_pref_program(valid_from: Date.new(2020, 1, 1), valid_until: Date.new(2021, 1, 1))
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      assert_nil verdict_for(prog, shinjuku_profile)
    end

    test "program for a different target is excluded" do
      prog = tokyo_pref_program(target: "business")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      assert_nil verdict_for(prog, shinjuku_profile(target: "individual"))
    end

    test "category filter narrows results" do
      prog = tokyo_pref_program(category: "控除")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      assert_nil KyufyCore.assess(profile: shinjuku_profile, categories: %w[給付金])
        .program_results.find { |pr| pr.program_id == prog.prefix_id }
      assert KyufyCore.assess(profile: shinjuku_profile, categories: %w[控除])
        .program_results.find { |pr| pr.program_id == prog.prefix_id }
    end

    test "national program is assessed regardless of residence" do
      prog = build_program(jurisdiction: "national", prefecture_code: nil, municipality_code: nil)
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      assert_equal :eligible, verdict_for(prog, shinjuku_profile)
    end

    # --- carve-out cap (§6 step 4) ---

    test "ancestor residence passes through and is capped at 要確認 (not dropped)" do
      # profile 東京都 vs a 新宿区-scoped municipality program, all real requirements met.
      prog = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13104")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      pr = KyufyCore.assess(profile: shinjuku_profile(residence: "東京都"))
        .program_results.find { |x| x.program_id == prog.prefix_id }
      refute_nil pr, "ancestor-residence program must remain in the result"
      assert_equal :needs_review, pr.verdict
      residence_reason = pr.reasons.find { |r| r[:kind] == :residence }
      assert residence_reason, "a synthesized residence reason must be present"
      assert_equal :unavailable, residence_reason[:citation_status]
      assert residence_reason[:source_url], "residence reason still carries the official_url"
    end

    test "carve-out cap holds even when the program has NO residence requirement row" do
      # The key case: geography is program-level, so a ward program may carry no residence
      # Requirement. Without the cap, an ancestor-residence profile whose other requirements all
      # pass would wrongly aggregate to 該当.
      prog = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13104")
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })     # met
      add_requirement(prog, kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }) # met
      assert_nil prog.requirements.find_by(kind: "residence"), "fixture must have no residence requirement"
      pr = KyufyCore.assess(profile: shinjuku_profile(residence: "東京都"))
        .program_results.find { |x| x.program_id == prog.prefix_id }
      assert_equal :needs_review, pr.verdict, "must be capped at 要確認, never 該当"
    end

    test "carve-out cap does not rescue a definitive 非該当" do
      prog = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13104")
      add_requirement(prog, kind: "income", operator: "lte", value: { "threshold" => 2_560_000 }) # not met
      pr = KyufyCore.assess(profile: shinjuku_profile(residence: "東京都", prior_year_income_jpy: 9_000_000))
        .program_results.find { |x| x.program_id == prog.prefix_id }
      assert_equal :ineligible, pr.verdict
    end

    test "residence normalization failure passes non-national programs through, capped at 要確認" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      pr = KyufyCore.assess(profile: shinjuku_profile(residence: "判別不能な住所"))
        .program_results.find { |x| x.program_id == prog.prefix_id }
      refute_nil pr, "normalization failure must not silently drop the program"
      assert_equal :needs_review, pr.verdict
    end

    # --- residence requirement decided by the geographic admission ---

    test "a residence requirement is satisfied by a geographic match (該当), keeping its citation" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      add_requirement(prog, kind: "residence", operator: "eq", value: { "eq" => "都内" }, raw_text: "都内に住所を有すること")
      pr = KyufyCore.assess(profile: shinjuku_profile).program_results.find { |x| x.program_id == prog.prefix_id }

      residence = pr.reasons.find { |r| r[:kind] == :residence }
      assert_equal :eligible, residence[:verdict], "matched residence resolves to 該当"
      assert_equal "都内に住所を有すること", residence[:citation], "citation is preserved"
      assert_equal :eligible, pr.verdict, "an in-scope resident with all requirements met is 該当"
    end

    test "a residence requirement on a carve-out program stays 要確認 with no duplicate synthesized reason" do
      prog = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13104")
      add_requirement(prog, kind: "residence", operator: "eq", value: { "eq" => "新宿区" }, raw_text: "新宿区に住民登録があること")
      pr = KyufyCore.assess(profile: shinjuku_profile(residence: "東京都")) # ancestor admission
        .program_results.find { |x| x.program_id == prog.prefix_id }

      residence_reasons = pr.reasons.select { |r| r[:kind] == :residence }
      assert_equal 1, residence_reasons.length, "the requirement carries the cap — no extra synthesized reason"
      assert_equal :needs_review, residence_reasons.first[:verdict]
      assert_equal :needs_review, pr.verdict
    end

    # --- citation degradation (§6 fail-safe) ---

    test "a requirement with no citation degrades to 要確認 and keeps the program present" do
      prog = tokyo_pref_program
      # raw_text blank and no chunks -> no citation can be produced.
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 }, raw_text: "")
      pr = KyufyCore.assess(profile: shinjuku_profile)
        .program_results.find { |x| x.program_id == prog.prefix_id }
      refute_nil pr
      reason = pr.reasons.find { |r| r[:kind] == :age }
      assert_equal :needs_review, reason[:verdict]
      assert_equal :unavailable, reason[:citation_status]
      assert reason[:source_url], "citation_unavailable degradation still carries source_url"
    end

    test "every reason carries a citation or a citation_unavailable degradation" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      KyufyCore.assess(profile: shinjuku_profile).each do |pr|
        pr.reasons.each do |r|
          ok = (r[:citation_status] == :present && r[:citation]) ||
               (r[:citation_status] == :unavailable && r[:source_url])
          assert ok, "reason must have a citation or a citation_unavailable degradation with source_url"
        end
      end
    end

    test "output carries the fixed disclaimer" do
      prog = tokyo_pref_program
      add_requirement(prog, kind: "age", operator: "gte", value: { "threshold" => 18 })
      pr = KyufyCore.assess(profile: shinjuku_profile).program_results.first
      assert_equal KyufyCore::DISCLAIMER, pr.disclaimer
    end
  end
end
