module KyufyCore
  module Ingestion
    # Normalized intermediate representation of a program (§5). Adapters (outside this gem)
    # produce these; the Importer maps them 1:1 onto the §4 Program model.
    NormalizedProgram = Struct.new(
      :name, :authority, :jurisdiction,          # jurisdiction: "national"/"prefecture"/"municipality"
      :prefecture_code, :municipality_code,      # JIS codes as strings, nullable per §4
      :category, :target, :official_url,
      :valid_from, :valid_until, :status,        # dates nullable; status defaults "active"
      :requirements,                             # [NormalizedRequirement]
      :source_documents,                         # [NormalizedDocument]
      :fetched_at,
      keyword_init: true
    )
  end
end
