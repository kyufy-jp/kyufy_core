module KyufyCore
  module Ingestion
    # Normalized 要綱 source document (§5). The Importer persists it as a SourceDocument, then
    # chunks its body and embeds each chunk via the configured embedding adapter.
    NormalizedDocument = Struct.new(
      :title, :url, :body, :fetched_at,
      :license,                                  # nullable, e.g. "CC-BY-4.0" — travels to SourceDocument
      keyword_init: true
    )
  end
end
