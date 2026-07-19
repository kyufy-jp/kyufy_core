require "json"

module KyufyCore
  module LLM
    # Shared base for real (network-backed) LLM adapters that ground per-requirement
    # explanations in the 要綱 excerpt. Subclasses implement only #complete_text (system:, user:)
    # -> String; this class owns the batched-per-program contract (§6 step 3), prompt building,
    # JSON parsing, and the fail-safe: verdicts always come from the rules, and any API failure
    # (error, refusal, unparseable output) degrades to a generic explanation rather than breaking
    # the assessment.
    class GroundedAdapter < Adapter
      MAX_TOKENS = 2048

      VERDICT_LABELS = {
        eligible: "該当", ineligible: "非該当", needs_review: "要確認"
      }.freeze

      SYSTEM_PROMPT = <<~PROMPT.freeze
        あなたは日本の公的給付制度（給付金・補助金・助成金・手当・控除）の要件判定を説明するアシスタントです。
        各要件について、与えられた要綱の抜粋（raw_text）と機械判定の結果（verdict）に基づき、日本語で簡潔な説明文を作成してください。
        判定自体は変更せず、なぜその判定になるのかを要綱の文言に即して説明します。根拠のない断定は避けてください。
        出力は必ずJSON配列のみとし、前後に説明文を付けないでください:
        [{"index": <整数>, "explanation": "<説明>"}, ...]
      PROMPT

      def assess_program(program:, items:)
        explanations = generate_explanations(program, items)
        items.each_with_index.map do |item, i|
          {
            id: item[:id],
            verdict: item[:rule_verdict],
            explanation: explanations[i] || fallback_explanation(program, item)
          }
        end
      rescue StandardError => e
        warn "[KyufyCore] #{self.class.name} fell back to generic explanations: #{e.class}: #{e.message}"
        items.map { |item| { id: item[:id], verdict: item[:rule_verdict], explanation: fallback_explanation(program, item) } }
      end

      private

      # @return [String] the model's raw text response. Return "" to trigger fallbacks
      # (e.g. on a refusal). Subclasses implement this.
      def complete_text(system:, user:)
        raise NotImplementedError, "#{self.class} must implement #complete_text"
      end

      def generate_explanations(program, items)
        text = complete_text(system: SYSTEM_PROMPT, user: user_prompt(program, items))
        parse_explanations(text, items.length)
      end

      def user_prompt(program, items)
        requirements = items.each_with_index.map do |item, i|
          {
            index: i,
            kind: item[:kind],
            verdict: VERDICT_LABELS.fetch(item[:rule_verdict], "要確認"),
            raw_text: item[:raw_text].to_s
          }
        end

        <<~USER
          制度名: #{program.name}

          以下の各要件について説明文を作成してください:
          #{JSON.generate(requirements)}
        USER
      end

      # Parse the model's JSON array into a position-indexed list of explanations.
      def parse_explanations(text, count)
        json = text.to_s[/\[.*\]/m]
        return [] unless json

        result = Array.new(count)
        JSON.parse(json).each do |entry|
          index = entry["index"]
          result[index] = entry["explanation"] if index.is_a?(Integer) && index.between?(0, count - 1)
        end
        result
      rescue JSON::ParserError
        []
      end

      def fallback_explanation(program, item)
        excerpt = item[:raw_text].to_s.strip
        if excerpt.empty?
          "#{program.name}の要件（#{item[:kind]}）について判定しました。"
        else
          "要綱「#{excerpt}」に基づき判定しました。"
        end
      end
    end
  end
end
