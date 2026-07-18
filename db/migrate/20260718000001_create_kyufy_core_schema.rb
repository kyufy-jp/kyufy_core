class CreateKyufyCoreSchema < ActiveRecord::Migration[8.1]
  def change
    enable_extension "vector" unless extension_enabled?("vector")

    create_table :kyufy_core_programs do |t|
      t.string :name, null: false
      t.string :authority                       # 所管 (free text)
      t.string :jurisdiction, null: false       # national / prefecture / municipality
      t.string :prefecture_code                 # JIS X 0401 (2-digit); null for national
      t.string :municipality_code               # JIS X 0402 (5-digit); null for national/prefecture
      t.string :category, null: false           # 給付金 / 補助金 / 助成金 / 手当 / 控除 (Japanese literals)
      t.string :target                          # individual / business
      t.string :official_url, null: false
      t.date :valid_from                        # null = open start
      t.date :valid_until                       # null = open end
      t.string :status, null: false, default: "active"  # active / inactive
      t.timestamps
    end
    add_index :kyufy_core_programs, [ :jurisdiction, :prefecture_code, :municipality_code ],
      name: "idx_kyufy_core_programs_geo"
    add_index :kyufy_core_programs, :category
    add_index :kyufy_core_programs, :status

    create_table :kyufy_core_source_documents do |t|
      t.references :program, null: false, foreign_key: { to_table: :kyufy_core_programs }
      t.string :title, null: false
      t.string :url
      t.datetime :fetched_at
      t.text :body
      t.timestamps
    end

    create_table :kyufy_core_requirements do |t|
      t.references :program, null: false, foreign_key: { to_table: :kyufy_core_programs }
      t.references :source_document, foreign_key: { to_table: :kyufy_core_source_documents }
      t.string :kind, null: false               # income / age / residence / household / employment / other
      t.string :operator, null: false           # lt / lte / gt / gte / eq / in / exists
      t.jsonb :value, null: false, default: {}
      t.text :raw_text                          # the exact 要綱 excerpt

      # CONDITION-TREE RESERVATION (§5): real programs contain composite conditions
      # ("A かつ B、ただし C を除く"). MVP keeps requirements flat and combines them with AND;
      # it does NOT evaluate a tree. These columns exist so the schema can become a condition
      # tree later (self-referencing parent + and/or/not logic) without a rewrite.
      t.references :parent, foreign_key: { to_table: :kyufy_core_requirements }
      t.string :logic                           # and / or / not — reserved, unused in MVP

      t.timestamps
    end

    create_table :kyufy_core_document_chunks do |t|
      t.references :source_document, null: false, foreign_key: { to_table: :kyufy_core_source_documents }
      t.text :content, null: false
      # EMBEDDING_DIM is fixed here at install time (default 1536, matches
      # KyufyCore.config.embedding_dim). Different embedding models have different dimensions;
      # changing this later means a migration + re-embedding every chunk.
      t.column :embedding, "vector(1536)"
      t.integer :position
      t.timestamps
    end
    # HNSW index (chosen over ivfflat). At MVP scale (3–5 programs) the index is optional, but
    # it costs nothing to create now.
    add_index :kyufy_core_document_chunks, :embedding,
      using: :hnsw, opclass: :vector_cosine_ops, name: "idx_kyufy_core_chunks_embedding_hnsw"
  end
end
