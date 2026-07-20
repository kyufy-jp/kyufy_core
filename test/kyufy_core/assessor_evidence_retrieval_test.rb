require "test_helper"

module KyufyCore
  # The pgvector citation back-fill (§6): a Requirement with no raw_text is cited from a
  # semantically-retrieved chunk. This exercises the query the Assessor sends to the Retriever —
  # it must be a meaningful Japanese phrase (EVIDENCE_QUERY), NOT the bare English kind label,
  # so the nearest-neighbour search lands on the on-topic chunk.
  #
  # Uses the deterministic Null embedding adapter: identical text hashes to an identical vector
  # (cosine distance 0), so the chunk whose content equals the query is the guaranteed nearest
  # neighbour. That lets us prove exactly which query string the Assessor used.
  class AssessorEvidenceRetrievalTest < ActiveSupport::TestCase
    # A national program (no geography to interfere) whose single income Requirement has no
    # raw_text, forcing citation_for down the retrieval back-fill path.
    def program_without_raw_text
      program = build_program(jurisdiction: "national", name: "所得要件テスト給付金")
      add_requirement(program, kind: "income", operator: "lte",
                      value: { "threshold" => 2_560_000 }, raw_text: nil)
      program
    end

    def with_chunks(program, contents)
      document = program.source_documents.create!(
        title: "要綱", url: "https://example.go.jp/youkou", body: contents.join, fetched_at: Time.now
      )
      embedder = KyufyCore.config.embedding_adapter
      contents.each_with_index do |content, position|
        document.document_chunks.create!(content: content, position: position, embedding: embedder.embed(content))
      end
      program
    end

    def income_citation(residence: "新宿区")
      KyufyCore.assess(profile: { residence: residence, target: "individual", prior_year_income_jpy: 864_000 })
        .program_results.find { |pr| pr.program_name == "所得要件テスト給付金" }
        .reasons.find { |r| r[:kind] == :income }[:citation]
    end

    test "a raw_text-less requirement is cited from the on-topic chunk, not the bare-kind chunk" do
      on_topic = Assessor::EVIDENCE_QUERY.fetch("income")
      program = program_without_raw_text
      # Under the deterministic Null adapter a chunk is the guaranteed nearest neighbour only when
      # its content equals the query string (cosine distance 0). "income" is exactly what the OLD
      # query embedded — it would win under the bug. The EVIDENCE_QUERY phrase is what the fixed
      # code embeds, so its matching chunk must win instead.
      with_chunks(program, [ "income", "年齢は18歳以上であること。", on_topic ])

      citation = income_citation
      assert_equal on_topic, citation, "the Japanese EVIDENCE_QUERY retrieves the on-topic chunk"
      refute_equal "income", citation, "the bare English kind label must not be the query"
    end

    test "citation back-fill still degrades to citation_unavailable when the program has no chunks" do
      program_without_raw_text # no document/chunks at all

      reason = KyufyCore.assess(profile: { residence: "新宿区", target: "individual", prior_year_income_jpy: 864_000 })
        .program_results.find { |pr| pr.program_name == "所得要件テスト給付金" }
        .reasons.find { |r| r[:kind] == :income }

      assert_nil reason[:citation]
      assert_equal :unavailable, reason[:citation_status]
      assert_match %r{\Ahttps?://}, reason[:source_url].to_s, "the official_url still travels with the reason"
    end
  end
end
