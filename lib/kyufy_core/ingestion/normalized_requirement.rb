module KyufyCore
  module Ingestion
    # Normalized requirement (§5). `value` follows §4 semantics (income = prior-year 所得 by
    # default). `document_ref` is an Integer index into the owning NormalizedProgram's
    # source_documents (0-based). Pinned to an integer index — NOT a key/string — so adapter
    # authors outside this gem don't have to guess the type.
    NormalizedRequirement = Struct.new(
      :kind, :operator, :value,
      :raw_text,
      :document_ref,
      keyword_init: true
    )
  end
end
