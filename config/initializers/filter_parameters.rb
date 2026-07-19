# Log hygiene (§7, mandatory). The Profile is never persisted, but a POST to the JSON API would
# otherwise land verbatim in the host's request logs. Engine config/initializers run during host
# boot, so this appends the Profile fields to the host's filter_parameters.
#
# Acknowledged tradeoff (§7): this mutates the host app's global filter list, and generic keys
# like :age / :employment will also mask the host's unrelated params of the same name.
# Over-filtering is the safe direction for this domain, so it is intentional — documented in the
# README so hosts aren't surprised.
Rails.application.config.filter_parameters += %i[
  residence prior_year_income_jpy age household_size employment
]
