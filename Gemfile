source "https://rubygems.org"

# Specify your gem's dependencies in kyufy_core.gemspec.
gemspec

gem "puma"

gem "pg"

gem "propshaft"

# Optional LLM adapter dependency (not a gemspec runtime dep — host apps that use only the
# Null adapters don't need it). Required lazily by KyufyCore::LLM::AnthropicAdapter.
gem "anthropic"

# Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
gem "rubocop-rails-omakase", require: false

# Start debugger with binding.b [https://github.com/ruby/debug]
# gem "debug", ">= 1.0.0"
