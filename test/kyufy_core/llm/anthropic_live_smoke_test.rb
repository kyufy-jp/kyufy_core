require "test_helper"

module KyufyCore
  module LLM
    # LIVE smoke test — makes a real Claude API call. Gated on ENV["KYUFY_ANTHROPIC_API_KEY"]:
    # runs only when the dedicated key is present, skips cleanly otherwise, so the suite stays
    # green with zero network on machines without the key. The key is read from ENV only and is
    # never written to any file in the repo.
    #
    #   KYUFY_ANTHROPIC_API_KEY=... bin/rails test test/kyufy_core/llm/anthropic_live_smoke_test.rb
    class AnthropicLiveSmokeTest < ActiveSupport::TestCase
      setup do
        skip "KYUFY_ANTHROPIC_API_KEY not set — skipping live Anthropic smoke test" unless ENV["KYUFY_ANTHROPIC_API_KEY"].present?
        KyufyCore.configure { |c| c.llm_adapter = AnthropicAdapter.new } # embedding stays Null (no embedding network)
        KyufyCore.import_yaml
      end

      test "real Claude explanations are grounded, with a quoted excerpt and official_url" do
        result = KyufyCore.assess(
          profile: { age: 52, residence: "新宿区", household_size: 3,
                     prior_year_income_jpy: 864_000, employment: "self_employed", target: "individual" },
          categories: %w[給付金 手当 控除]
        )

        tokyo = result.program_results.find { |pr| pr.program_name == "東京都子育て世帯物価高騰支援給付金" }
        refute_nil tokyo, "the seeded Tokyo program must be assessed"
        assert_equal :eligible, tokyo.verdict

        graded = tokyo.reasons.reject { |r| r[:kind] == :residence } # skip synthesized reasons
        assert graded.any?

        graded.each do |reason|
          assert reason[:citation].to_s.strip.length.positive?, "each reason carries a quoted 要綱 excerpt"
          assert reason[:citation].to_s.length <= 60, "citation is a short quote (~40字), not the whole document"
          assert_match %r{\Ahttps?://}, reason[:source_url].to_s, "each reason carries the official_url"
          assert reason[:explanation].to_s.strip.length.positive?, "Claude produced a non-empty explanation"
        end

        # Surface the real output so explanation quality can be eyeballed.
        puts "\n--- Live Claude explanations (東京都子育て世帯物価高騰支援給付金 => #{tokyo.verdict}) ---"
        graded.each do |reason|
          puts "[#{reason[:kind]}] #{reason[:verdict]}"
          puts "  引用: #{reason[:citation]}"
          puts "  説明: #{reason[:explanation]}"
          puts "  出典: #{reason[:source_url]}"
        end
      end
    end
  end
end
