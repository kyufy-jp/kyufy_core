module KyufyCore
  # 制度. Geographic scoping lives here (prefecture_code / municipality_code) — see Geo for the
  # hierarchy semantics. External identifier: prog_… (never expose the raw bigint PK).
  class Program < ApplicationRecord
    has_prefix_id :prog

    # 給付金 / 補助金 / 助成金 / 手当 / 控除 — kept as Japanese literals on purpose (§0 domain
    # terms). A validated string column rather than an AR enum so category filtering can query
    # the Japanese values directly.
    CATEGORIES = %w[給付金 補助金 助成金 手当 控除].freeze

    enum :jurisdiction, { national: "national", prefecture: "prefecture", municipality: "municipality" }
    enum :target, { individual: "individual", business: "business" }
    enum :status, { active: "active", inactive: "inactive" }, default: "active"

    has_many :requirements, class_name: "KyufyCore::Requirement", dependent: :destroy
    has_many :source_documents, class_name: "KyufyCore::SourceDocument", dependent: :destroy

    validates :name, presence: true
    validates :official_url, presence: true
    validates :category, inclusion: { in: CATEGORIES }
    validates :prefecture_code, presence: true, unless: :national?
    validates :municipality_code, presence: true, if: :municipality?
  end
end
