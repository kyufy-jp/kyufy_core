require "test_helper"

module KyufyCore
  class IngestionTest < ActiveSupport::TestCase
    test "ManualYamlAdapter + Importer persist the packaged seed with chunks + embeddings" do
      programs = KyufyCore.import_yaml
      assert_equal 5, programs.size

      tokyo = KyufyCore::Program.find_by!(name: "東京都子育て世帯物価高騰支援給付金")
      assert_equal "prefecture", tokyo.jurisdiction
      assert_equal "13", tokyo.prefecture_code
      assert_equal 2, tokyo.requirements.count
      assert_equal 1, tokyo.source_documents.count

      chunks = tokyo.source_documents.first.document_chunks
      assert chunks.any?, "document must be chunked + embedded"
      assert_equal KyufyCore.config.embedding_dim, chunks.first.embedding.size
    end

    test "document_ref (0-based integer) links a requirement to its source document" do
      KyufyCore.import_yaml
      KyufyCore::Requirement.includes(:program).find_each do |req|
        assert_equal req.program.source_documents.first.id, req.source_document_id
      end
    end

    # This test doubles as executable documentation of the §11 demo: a single profile produces
    # the full spread of verdicts across the seeded programs.
    test "the demo 新宿区 profile produces 該当 / 非該当 / 要確認 across the seed" do
      KyufyCore.import_yaml
      result = KyufyCore.assess(
        profile: { age: 52, residence: "新宿区", household_size: 3,
                   prior_year_income_jpy: 864_000, employment: "self_employed", target: "individual" }
      )
      by_name = result.program_results.to_h { |pr| [ pr.program_name, pr.verdict ] }

      assert_equal :eligible,     by_name["定額減税（所得税・個人住民税）"]
      assert_equal :eligible,     by_name["東京都子育て世帯物価高騰支援給付金"]
      assert_equal :ineligible,   by_name["新宿区高齢者福祉タクシー利用助成"]   # age 52 < 65
      assert_equal :needs_review, by_name["新宿区就学援助"]                       # undeterminable requirement
      assert_nil   by_name["さいたま市子育て応援給付金"], "different prefecture -> excluded"
    end

    test "switching residence to さいたま surfaces the Saitama program (cross-municipality)" do
      KyufyCore.import_yaml
      result = KyufyCore.assess(
        profile: { age: 40, residence: "さいたま市中央区", household_size: 3,
                   prior_year_income_jpy: 864_000, target: "individual" }
      )
      names = result.program_results.map(&:program_name)
      assert_includes names, "さいたま市子育て応援給付金"
      refute_includes names, "東京都子育て世帯物価高騰支援給付金", "Tokyo programs drop out for a Saitama resident"
    end
  end
end
