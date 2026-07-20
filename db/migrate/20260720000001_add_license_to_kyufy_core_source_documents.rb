class AddLicenseToKyufyCoreSourceDocuments < ActiveRecord::Migration[8.1]
  def change
    # Per-dataset license (e.g. "CC-BY-4.0"), captured at ingestion so attribution can travel
    # with the data to the assessment output (§4/§7). Nullable — hand-authored / uniformly-licensed
    # sources may leave it blank.
    add_column :kyufy_core_source_documents, :license, :string
  end
end
