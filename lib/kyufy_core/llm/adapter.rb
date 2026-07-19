module KyufyCore
  module LLM
    # Abstract LLM adapter (§8). The contract is BATCHED PER PROGRAM (§6 step 3): one call
    # grounds all of a program's requirements at once — N×M sequential calls don't scale, and
    # the adapter interface reflects batching from day one.
    #
    # #assess_program is given the program and one item per requirement:
    #   item = { id:, kind:, raw_text:, rule_verdict: (:eligible/:ineligible/:needs_review) }
    #
    # It must return one entry per item (same :id) with a grounded natural-language
    # :explanation. It MAY echo a :verdict, but the rule's verdict wins for anything the rule
    # already decided, and undeterminable requirements stay 要確認 (fail-safe) — so the
    # explanation is the adapter's real job here.
    class Adapter
      # @return [Array<Hash{id:, verdict:, explanation:}>]
      def assess_program(program:, items:)
        raise NotImplementedError, "#{self.class} must implement #assess_program"
      end
    end
  end
end
