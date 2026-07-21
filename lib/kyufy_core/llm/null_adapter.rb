module KyufyCore
  module LLM
    # Deterministic, no-network LLM adapter for tests and offline runs (§8). Produces a
    # grounded explanation from the requirement's own 要綱 excerpt and echoes the rule verdict
    # (it never fabricates a verdict for an undeterminable requirement — fail-safe keeps those
    # at 要確認). Fast, free, reproducible, zero API calls.
    class NullAdapter < Adapter
      VERDICT_LABELS = {
        eligible: "該当", ineligible: "非該当", needs_review: "要確認"
      }.freeze

      def assess_program(program:, items:, plain_language: false)
        prefix = plain_language ? "【やさしい日本語】" : ""
        items.map do |item|
          label = VERDICT_LABELS.fetch(item[:rule_verdict], "要確認")
          # `kind` is an English enum, but these sentences are read by Japanese users — a bare
          # "income の要件" reads as broken Japanese, so use the canonical Japanese label.
          kind_label = Requirement.kind_label(item[:kind])
          excerpt = item[:raw_text].to_s.strip
          explanation =
            if excerpt.empty?
              "#{prefix}#{program.name}の要件（#{kind_label}）について、根拠となる要綱本文を特定できませんでした。"
            else
              "#{prefix}要綱「#{excerpt}」に基づき、#{kind_label}の要件を#{label}と判定しました。"
            end

          { id: item[:id], verdict: item[:rule_verdict], explanation: explanation }
        end
      end
    end
  end
end
