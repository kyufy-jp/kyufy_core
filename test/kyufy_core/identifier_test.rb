require "test_helper"

module KyufyCore
  # §4 identifier guarantee: JSON/API output and Result objects expose prefixed IDs only,
  # never raw bigint PKs.
  class IdentifierTest < ActiveSupport::TestCase
    setup do
      @program = build_program(jurisdiction: "prefecture", prefecture_code: "13")
      add_requirement(@program, kind: "age", operator: "gte", value: { "threshold" => 18 })
    end

    def assess
      KyufyCore.assess(profile: { age: 52, residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 })
    end

    test "program_id and requirement_id are prefixed, not raw PKs" do
      pr = assess.program_results.first
      assert_match(/\Aprog_/, pr.program_id)
      refute_equal @program.id.to_s, pr.program_id
      pr.reasons.each do |reason|
        next if reason[:requirement_id].nil? # synthesized reasons have no requirement
        assert_match(/\Areq_/, reason[:requirement_id])
      end
    end

    test "no raw PK value appears anywhere in the serialized result" do
      raw_ids = [ @program.id, @program.requirements.first.id ].map(&:to_s)
      json = assess.as_json.to_json
      raw_ids.each do |raw|
        # A bare integer PK must not surface as an id value in the JSON payload.
        refute_match(/"(program_id|requirement_id)"\s*:\s*"?#{raw}"?/, json)
      end
    end

    test "DocumentChunk has no prefixed id (purely internal)" do
      refute_respond_to KyufyCore::DocumentChunk.new, :prefix_id
    end
  end
end
