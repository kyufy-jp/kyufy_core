require_relative "lib/kyufy_core/version"

Gem::Specification.new do |spec|
  spec.name        = "kyufy_core"
  spec.version     = KyufyCore::VERSION
  spec.authors     = [ "kyufy" ]
  spec.email       = [ "maurois@mac.com" ]
  spec.homepage    = "https://github.com/dadachi/kyufy_core"
  spec.summary     = "Assessment engine for Japanese public-benefit eligibility (給付金・補助金・助成金・手当・控除)."
  spec.description = "kyufy-core is the open-source assessment engine: it takes a profile and a " \
                     "program's requirements and returns 該当 / 非該当 / 要確認 with cited evidence " \
                     "(a quoted excerpt from the 要綱 + official source URL), grounded via a swappable " \
                     "LLM adapter and pgvector retrieval. A Rails reimplementation of the structure of " \
                     "Digital Agency's 源内 administrative RAG."
  spec.license     = "MIT"

  spec.required_ruby_version = ">= 3.2"

  spec.metadata["homepage_uri"]    = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/dadachi/kyufy_core"
  spec.metadata["changelog_uri"]   = "https://github.com/dadachi/kyufy_core/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(File.expand_path(__dir__)) do
    Dir["{app,config,db,lib}/**/*", "MIT-LICENSE", "Rakefile", "README.md"]
  end

  # Development targets Rails 8.1.3 / Ruby 4.0.6 (pinned in test/dummy and .ruby-version),
  # but the gem must not pin patch versions: a gem pinning "= 8.1.3" becomes uninstallable
  # the day a host bumps to 8.1.4.
  spec.add_dependency "rails", ">= 8.1", "< 9"

  # External identifiers (never expose raw bigint PKs across the API boundary).
  spec.add_dependency "prefixed_ids"

  # pgvector <-> ActiveRecord integration (vector column type + nearest-neighbor scopes).
  spec.add_dependency "neighbor"
end
