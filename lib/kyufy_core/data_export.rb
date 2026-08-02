require "json"
require "yaml"
require "fileutils"
require_relative "geo"
require_relative "ingestion/source"
require_relative "ingestion/normalized_program"
require_relative "ingestion/normalized_requirement"
require_relative "ingestion/normalized_document"
require_relative "ingestion/manual_yaml_adapter"

module KyufyCore
  # Regenerates the committed JSON under data/ — the two datasets in this gem that are worth
  # reusing outside Ruby: Geo's JIS code tables (locked in Ruby constants until now) and the
  # five real seed programs with their verbatim 要綱 excerpts and provenance.
  #
  # Deliberately NOT required from lib/kyufy_core.rb: nothing at runtime needs it, so host apps
  # shouldn't pay for it. Loaded only by `rake data:export` and the drift test, both of which
  # require it directly. Plain Ruby — no Rails, no database.
  #
  # The exports are derived, never authoritative: Geo's constants and db/seeds/programs/*.yml
  # stay the single source of truth, and test/kyufy_core/data_export_test.rb fails if the
  # committed files drift from them.
  module DataExport
    ROOT = File.expand_path("../..", __dir__)
    SEED_DIR = File.join(ROOT, "db", "seeds", "programs").freeze

    GEO_PATH = "data/geo.json".freeze
    PROGRAMS_PATH = "data/programs.json".freeze

    module_function

    # { relative path => JSON-safe content }. Both the writer and the drift test read this, so
    # what gets compared is exactly what gets written.
    def documents
      { GEO_PATH => geo, PROGRAMS_PATH => programs }
    end

    def write_all(root = ROOT)
      documents.map do |relative_path, content|
        path = File.join(root, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, "#{JSON.pretty_generate(content)}\n")
        path
      end
    end

    def geo
      json_safe(
        "_meta" => {
          "description" => "JIS code tables and designated-city data backing KyufyCore::Geo.",
          "generated_from" => "lib/kyufy_core/geo.rb",
          "regenerate_with" => "bundle exec rake data:export",
          "codes" => "Prefecture codes are JIS X 0401 (2-digit), municipality codes JIS X 0402 " \
                     "(5-digit). Both are STRINGS: leading zeros are significant (札幌市 = \"01100\").",
          "municipalities_coverage" => "PARTIAL, NOT a national table — only the 東京都特別区 (23) " \
                                       "and さいたま市 + its 10 wards, which is what the seed and " \
                                       "tests need. Do not treat a lookup miss as 'no such city'.",
          "ambiguous_names" => "Bare duplicate ward names (中央区, 北区, 南区, …) are deliberately " \
                               "absent: several cities have one, so a bare name cannot be resolved. " \
                               "The engine treats the miss as a normalization failure and degrades " \
                               "to 要確認 rather than matching the wrong municipality. Disambiguated " \
                               "keys (中央区（東京都）, さいたま市中央区) are present.",
          "designated_cities" => "The 20 政令指定都市, the only data the ward→parent-city logic " \
                                 "needs. 東京23区 are absent on purpose: each 特別区 is a full " \
                                 "municipality with no parent city, so they resolve to no parent."
        },
        "prefectures" => Geo::PREFECTURES,
        "designated_cities" => Geo::DESIGNATED_CITY_CODES,
        "municipalities" => Geo::MUNICIPALITIES
      )
    end

    def programs
      entries = Dir[File.join(SEED_DIR, "*.yml")].sort.flat_map do |path|
        source_file = File.basename(path)
        Ingestion::ManualYamlAdapter.from_file(path).fetch_programs.map do |program|
          program_hash(program, source_file)
        end
      end

      json_safe(
        "_meta" => {
          "description" => "The five real seed programs, parsed by the same adapter the engine " \
                           "imports with (Ingestion::ManualYamlAdapter), so this is what the " \
                           "assessment actually sees.",
          "generated_from" => "db/seeds/programs/*.yml",
          "regenerate_with" => "bundle exec rake data:export",
          "raw_text" => "Every requirement's raw_text is a VERBATIM excerpt from the linked " \
                        "official page — it is the citation the engine quotes. Never paraphrase it.",
          "license" => "A source document's license is null when the publisher states no open " \
                       "license. Null means 'unknown, assume all rights reserved', not 'free'.",
          "freshness" => "fetched_at records when the text was read. Programs change; re-fetch " \
                         "before relying on any of this.",
          "schema" => "data/README.md"
        },
        "programs" => entries
      )
    end

    # --- helpers -------------------------------------------------------------------------

    def program_hash(program, source_file)
      {
        "source_file" => source_file,
        "name" => program.name,
        "authority" => program.authority,
        "jurisdiction" => program.jurisdiction,
        "prefecture_code" => program.prefecture_code,
        "municipality_code" => program.municipality_code,
        "category" => program.category,
        "target" => program.target,
        "official_url" => program.official_url,
        "valid_from" => date_string(program.valid_from),
        "valid_until" => date_string(program.valid_until),
        "status" => program.status,
        "source_documents" => Array(program.source_documents).map { |doc| document_hash(doc) },
        "requirements" => Array(program.requirements).map { |req| requirement_hash(req) }
      }
    end

    def document_hash(document)
      {
        "title" => document.title,
        "url" => document.url,
        "fetched_at" => date_string(document.fetched_at),
        "license" => document.license,
        "body" => document.body
      }
    end

    def requirement_hash(requirement)
      {
        "kind" => requirement.kind,
        "operator" => requirement.operator,
        "value" => requirement.value || {},
        "raw_text" => requirement.raw_text,
        "document_ref" => requirement.document_ref
      }
    end

    def date_string(value)
      value.nil? ? nil : value.to_s
    end

    # One round-trip so the in-memory structure is byte-identical to the file: YAML hands back
    # Dates and symbols the drift test would otherwise compare against parsed JSON strings.
    def json_safe(hash)
      JSON.parse(JSON.generate(hash))
    end
  end
end
