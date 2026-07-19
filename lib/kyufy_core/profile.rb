module KyufyCore
  # The user's situation (§7). Never persisted — a value object passed in at assess time
  # (PII stays out of the database). `residence` is free text; it is normalized to JIS codes
  # lazily via Geo. `prior_year_income_jpy` is 所得 (net/taxable), NOT 収入 (gross) — the field
  # name forces the choice (§4 income semantics).
  class Profile
    ATTRIBUTES = %i[age residence household_size prior_year_income_jpy employment target].freeze

    attr_reader(*ATTRIBUTES)

    # Accepts a Profile (passthrough) or a Hash with string/symbol keys.
    def self.wrap(input)
      return input if input.is_a?(Profile)

      new(**input.to_h.symbolize_keys.slice(*ATTRIBUTES))
    end

    def initialize(age: nil, residence: nil, household_size: nil,
                   prior_year_income_jpy: nil, employment: nil, target: nil)
      @age                   = age
      @residence             = residence
      @household_size        = household_size
      @prior_year_income_jpy = prior_year_income_jpy
      @employment            = employment
      @target                = target
    end

    # Normalized residence (Geo::Residence) or nil when normalization fails.
    # nil triggers carve-out (a) in the Assessor: geography must not exclude, and
    # residence-dependent programs resolve to 要確認.
    def normalized_residence
      return @normalized_residence if defined?(@normalized_residence)

      @normalized_residence = Geo.normalize(residence)
    end

    def residence_normalized?
      !normalized_residence.nil?
    end

    # Machine-readable value for a Requirement kind, or nil if the profile can't supply it.
    def value_for(kind)
      case kind.to_s
      when "income"     then prior_year_income_jpy
      when "age"        then age
      when "household"  then household_size
      when "employment" then employment
      else nil
      end
    end
  end
end
