module KyufyCore
  # A 世帯 (household): members who share one residence. Many Japanese benefits are assessed at
  # the household level — income is summed across members (世帯合算所得) and eligibility keys on
  # composition — so a household is a first-class subject, not just a bag of profiles.
  #
  # Members share a residence by definition; a household whose members resolve to different
  # municipalities/prefectures is rejected (that's the "different residence" mistake made
  # explicit).
  class Household
    attr_reader :members

    # Accepts a Household (passthrough), a Hash with :members, or a bare Array of members.
    def self.wrap(input)
      return input if input.is_a?(Household)

      members = input.is_a?(Hash) ? (input[:members] || input["members"]) : input
      new(members: members)
    end

    def initialize(members:)
      @members = Array(members).map { |m| Profile.wrap(m) }
      raise KyufyCore::Error, "a household needs at least one member" if @members.empty?

      validate_shared_residence!
    end

    def size = members.size

    def residence = members.first.residence

    # 世帯合算所得: the household's combined prior-year 所得 (nil member income counts as 0).
    def total_income
      members.sum { |m| m.prior_year_income_jpy.to_i }
    end

    # A representative Profile for household-level assessment: the shared residence, the actual
    # member count, and 世帯合算所得. Per-member attributes (age, employment) are intentionally
    # left nil — they aren't household facts, so age/employment requirements resolve to 要確認
    # (fail-safe) when a program is assessed at the household level. Per-member eligibility is a
    # separate concern (KyufyCore.assess_batch).
    def to_profile
      Profile.new(
        residence: residence,
        household_size: size,
        prior_year_income_jpy: total_income,
        target: "individual"
      )
    end

    private

    def validate_shared_residence!
      codes = members.filter_map do |member|
        normalized = member.normalized_residence
        normalized&.municipality_code || normalized&.prefecture_code
      end
      return if codes.uniq.size <= 1

      raise KyufyCore::Error,
        "household members must share a residence (got #{members.map(&:residence).uniq.inspect})"
    end
  end
end
