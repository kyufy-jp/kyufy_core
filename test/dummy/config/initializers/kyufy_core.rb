# Adapter selection for the dummy host app (SPEC §8), driven by env so the Docker demo can
# opt into real models without a code change. Unset env = a no-op: the configured defaults are
# the Null adapters (no network, no credentials), which is what the test suite relies on.
KyufyCore.configure do |config|
  case ENV["KYUFY_LLM"]
  when "anthropic" then config.llm_adapter = KyufyCore::LLM::AnthropicAdapter.new
  when "openai"    then config.llm_adapter = KyufyCore::LLM::OpenAICompatibleAdapter.new
  end

  config.embedding_adapter = KyufyCore::Embedding::OpenAICompatibleAdapter.new if ENV["KYUFY_EMBEDDING"] == "openai"
end
