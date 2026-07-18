# Configure Rails Environment
ENV["RAILS_ENV"] = "test"

require_relative "../test/dummy/config/environment"
ActiveRecord::Migrator.migrations_paths = [ File.expand_path("../test/dummy/db/migrate", __dir__) ]
ActiveRecord::Migrator.migrations_paths << File.expand_path("../db/migrate", __dir__)
require "rails/test_help"

module KyufyCore
  # Record builders for tests. Vector-column fixtures are awkward, so build records directly
  # (embeddings come from the deterministic Null adapter).
  module TestBuilders
    def build_program(jurisdiction:, prefecture_code: nil, municipality_code: nil,
                      category: "給付金", target: "individual", status: "active",
                      valid_from: nil, valid_until: nil,
                      name: "テスト制度", official_url: "https://example.metro.jp/prog")
      KyufyCore::Program.create!(
        name: name, authority: "テスト所管", jurisdiction: jurisdiction,
        prefecture_code: prefecture_code, municipality_code: municipality_code,
        category: category, target: target, status: status,
        valid_from: valid_from, valid_until: valid_until, official_url: official_url
      )
    end

    def add_requirement(program, kind:, operator:, value: {}, raw_text: "要件の要綱抜粋。", source_document: nil)
      program.requirements.create!(
        kind: kind, operator: operator, value: value,
        raw_text: raw_text, source_document: source_document
      )
    end

    def add_document(program, title: "要綱", body: "要綱本文。", url: "https://example.metro.jp/youkou")
      embedder = KyufyCore.config.embedding_adapter
      document = program.source_documents.create!(title: title, url: url, body: body, fetched_at: Time.now)
      body.chars.each_slice(200).with_index do |slice, position|
        content = slice.join
        document.document_chunks.create!(content: content, position: position, embedding: embedder.embed(content))
      end
      document
    end
  end
end

class ActiveSupport::TestCase
  include KyufyCore::TestBuilders

  # Each test starts from the default (Null) adapters + default embedding_dim.
  setup { KyufyCore.instance_variable_set(:@configuration, nil) }
  teardown { KyufyCore.instance_variable_set(:@configuration, nil) }
end
