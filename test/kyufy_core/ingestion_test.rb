require "test_helper"

module KyufyCore
  class IngestionTest < ActiveSupport::TestCase
    test "ManualYamlAdapter + Importer persist the packaged Tokyo seed with chunks + embeddings" do
      programs = KyufyCore.import_yaml
      assert_equal 1, programs.size

      program = programs.first
      assert_equal "prefecture", program.jurisdiction
      assert_equal "13", program.prefecture_code
      assert_equal 2, program.requirements.count
      assert_equal 1, program.source_documents.count

      chunks = program.source_documents.first.document_chunks
      assert chunks.any?, "document must be chunked + embedded"
      assert_equal KyufyCore.config.embedding_dim, chunks.first.embedding.size
    end

    test "document_ref (0-based integer) links a requirement to its source document" do
      program = KyufyCore.import_yaml.first
      program.requirements.each do |req|
        assert_equal program.source_documents.first.id, req.source_document_id
      end
    end

    test "the seeded Tokyo program assesses as eligible for the demo 新宿区 profile" do
      KyufyCore.import_yaml
      result = KyufyCore.assess(
        profile: { age: 52, residence: "新宿区", household_size: 3,
                   prior_year_income_jpy: 864_000, employment: "self_employed", target: "individual" },
        categories: %w[給付金 手当 控除]
      )
      pr = result.program_results.first
      assert_equal :eligible, pr.verdict
      assert(pr.reasons.all? { |r| r[:citation_status] == :present })
    end
  end
end
