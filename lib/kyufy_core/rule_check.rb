module KyufyCore
  # Machine-readable first pass (§6 step 1): match one Requirement against the Profile.
  # Returns :met, :not_met, or :undeterminable. Missing info -> :undeterminable, which the
  # Assessor maps to 要確認 (fail-safe). Never guesses.
  #
  # `value` (jsonb) shape by operator:
  #   lt / lte / gt / gte  -> { "threshold" => <number> }
  #   eq                   -> { "eq" => <value> }
  #   in                   -> { "in" => [<value>, ...] }
  #   exists               -> {} (presence of the profile field)
  # For kind "income", the operand is prior-year 所得 (JPY) unless value has
  # { "measure" => "収入" } — which the Profile can't supply, so it's undeterminable.
  module RuleCheck
    module_function

    def evaluate(requirement, profile)
      kind = requirement.kind.to_s
      value = requirement.value.is_a?(Hash) ? requirement.value : {}

      return :undeterminable if kind == "income" && value["measure"] == "収入"

      actual = profile.value_for(kind)
      operator = requirement.operator.to_s

      return presence(actual) if operator == "exists"
      return :undeterminable if actual.nil?

      case operator
      when "lt"  then compare(actual, value) { |a, b| a < b }
      when "lte" then compare(actual, value) { |a, b| a <= b }
      when "gt"  then compare(actual, value) { |a, b| a > b }
      when "gte" then compare(actual, value) { |a, b| a >= b }
      when "eq"  then value.key?("eq") ? boolify(actual == value["eq"]) : :undeterminable
      when "in"  then membership(actual, value["in"])
      else :undeterminable
      end
    end

    def presence(actual)
      actual.nil? ? :not_met : :met
    end

    def compare(actual, value)
      threshold = value["threshold"]
      return :undeterminable unless numeric?(actual) && numeric?(threshold)

      boolify(yield(Float(actual), Float(threshold)))
    end

    def membership(actual, set)
      return :undeterminable unless set.is_a?(Array)

      boolify(set.include?(actual))
    end

    def numeric?(x)
      Float(x, exception: false) ? true : false
    end

    def boolify(bool)
      bool ? :met : :not_met
    end
  end
end
