require "yaml"
require "date"

module KyufyCore
  module Ingestion
    # Hand-written YAML -> NormalizedProgram (§5). The MVP uses ONLY this source; richer
    # per-municipality adapters (catalog CSV, HTML/PDF scrape, LLM extraction) live in the
    # separate kyufy-adapters gem. A minimal copy ships here because the seed needs it.
    class ManualYamlAdapter < Source
      def self.from_file(path)
        new(File.read(path))
      end

      def initialize(yaml)
        @yaml = yaml
      end

      def fetch_programs
        entries = YAML.safe_load(@yaml, permitted_classes: [ Date, Time ], aliases: true) || []
        entries.map { |e| build_program(e) }
      end

      private

      def build_program(entry)
        NormalizedProgram.new(
          name: entry["name"],
          authority: entry["authority"],
          jurisdiction: entry["jurisdiction"],
          prefecture_code: entry["prefecture_code"],
          municipality_code: entry["municipality_code"],
          category: entry["category"],
          target: entry["target"],
          official_url: entry["official_url"],
          valid_from: entry["valid_from"],
          valid_until: entry["valid_until"],
          status: entry["status"] || "active",
          fetched_at: entry["fetched_at"],
          source_documents: Array(entry["source_documents"]).map { |d| build_document(d) },
          requirements: Array(entry["requirements"]).map { |r| build_requirement(r) }
        )
      end

      def build_document(doc)
        NormalizedDocument.new(
          title: doc["title"],
          url: doc["url"],
          body: doc["body"],
          fetched_at: doc["fetched_at"],
          license: doc["license"]
        )
      end

      def build_requirement(req)
        NormalizedRequirement.new(
          kind: req["kind"],
          operator: req["operator"],
          value: req["value"] || {},
          raw_text: req["raw_text"],
          document_ref: req["document_ref"]
        )
      end
    end
  end
end
