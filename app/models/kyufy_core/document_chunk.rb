module KyufyCore
  # A chunk of 要綱 text + its embedding — the hottest pgvector path. Deliberately has NO
  # prefixed id (§4): purely internal, structurally never exposed — what leaves the system is a
  # chunk's quoted text, not its id.
  class DocumentChunk < ApplicationRecord
    belongs_to :source_document, class_name: "KyufyCore::SourceDocument"

    # neighbor gem: nearest-neighbor scopes over the pgvector column.
    has_neighbors :embedding
  end
end
