require "kyufy_core/version"
require "kyufy_core/engine"

# Plain-Ruby collaborators (POROs, value objects, adapters, ingestion port).
# AR models live under app/models and are autoloaded by the engine; these are
# required explicitly so the engine's public API is available as soon as the gem loads.
require "kyufy_core/configuration"
require "kyufy_core/geo"
require "kyufy_core/profile"
require "kyufy_core/result"
require "kyufy_core/llm/adapter"
require "kyufy_core/llm/null_adapter"
require "kyufy_core/llm/grounded_adapter"
require "kyufy_core/llm/anthropic_adapter"
require "kyufy_core/llm/open_ai_compatible_adapter"
require "kyufy_core/embedding/adapter"
require "kyufy_core/embedding/null_adapter"
require "kyufy_core/embedding/open_ai_compatible_adapter"
require "kyufy_core/ingestion/normalized_program"
require "kyufy_core/ingestion/normalized_requirement"
require "kyufy_core/ingestion/normalized_document"
require "kyufy_core/ingestion/source"
require "kyufy_core/ingestion/importer"
require "kyufy_core/ingestion/manual_yaml_adapter"
require "kyufy_core/retriever"
require "kyufy_core/rule_check"
require "kyufy_core/assessor"

module KyufyCore
  # Fixed disclaimer that every assessment output must carry (§6 fail-safe).
  DISCLAIMER = "これは参考判定です。最終確認は各制度の公式窓口で行ってください。".freeze

  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end
    alias_method :config, :configuration

    def configure
      yield(configuration)
      configuration
    end

    # Public entry point (§7).
    #
    #   KyufyCore.assess(profile: { ... }, categories: %w[給付金 手当 控除])
    #
    # Pass `plain_language: true` to have explanations written in やさしい日本語 (easy Japanese)
    # — for users who find 要綱 wording hard to read. Returns a KyufyCore::Result. Exposes
    # prefixed IDs only, never raw PKs.
    def assess(profile:, categories: nil, plain_language: false)
      profile = Profile.wrap(profile)
      Assessor.new(profile: profile, categories: categories, plain_language: plain_language).call
    end

    # Packaged Tokyo seed data (§11).
    def seed_path
      Engine.root.join("db", "seeds", "tokyo_programs.yml")
    end

    # Ingest a YAML source file via ManualYamlAdapter -> Importer. Returns the created Programs.
    def import_yaml(path = seed_path)
      programs = Ingestion::ManualYamlAdapter.from_file(path).fetch_programs
      Ingestion::Importer.new.import(programs)
    end
  end
end
