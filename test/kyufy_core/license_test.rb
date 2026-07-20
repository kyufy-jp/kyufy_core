require "test_helper"

module KyufyCore
  # §4/§7 license threading: attribution travels from the cited SourceDocument to the output.
  class LicenseTest < ActiveSupport::TestCase
    def profile
      { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 }
    end

    test "a cited reason carries the source document's license when present" do
      program = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      document = program.source_documents.create!(
        title: "要綱", url: "https://example.jp", body: "本文", fetched_at: Time.now, license: "CC-BY-4.0"
      )
      add_requirement(program, kind: "age", operator: "gte", value: { "threshold" => 18 }, source_document: document)

      reason = KyufyCore.assess(profile: profile).program_results
        .find { |pr| pr.program_id == program.prefix_id }
        .reasons.find { |r| r[:kind] == :age }
      assert_equal "CC-BY-4.0", reason[:license]
    end

    test "a reason whose requirement has no source document carries license: nil" do
      program = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      add_requirement(program, kind: "age", operator: "gte", value: { "threshold" => 18 }) # no source_document

      reason = KyufyCore.assess(profile: profile).program_results
        .find { |pr| pr.program_id == program.prefix_id }
        .reasons.find { |r| r[:kind] == :age }
      assert_nil reason[:license]
    end

    test "synthesized (carve-out) reasons carry license: nil" do
      # 東京都 profile vs a 新宿区-scoped municipality program -> ancestor carve-out -> synthesized
      # residence_unverified reason, which cites no document.
      program = build_program(jurisdiction: "municipality", prefecture_code: "13", municipality_code: "13104")
      add_requirement(program, kind: "age", operator: "gte", value: { "threshold" => 18 })

      residence_reason = KyufyCore.assess(profile: profile.merge(residence: "東京都")).program_results
        .find { |pr| pr.program_id == program.prefix_id }
        .reasons.find { |r| r[:kind] == :residence && r[:requirement_id].nil? }
      refute_nil residence_reason, "carve-out adds a synthesized residence reason"
      assert_nil residence_reason[:license]
    end

    test "the packaged seed carries the license captured from each official page" do
      KyufyCore.import_dir
      mhlw = KyufyCore::Program.find_by!(name: "一般教育訓練給付金")
      assert_equal "PDL1.0", mhlw.source_documents.first.license, "MHLW content is PDL1.0"

      tokyo = KyufyCore::Program.find_by!(name: "018サポート")
      assert_nil tokyo.source_documents.first.license, "東京都福祉局 reserves rights -> no open license"
    end
  end
end
