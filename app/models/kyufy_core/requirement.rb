module KyufyCore
  # 要件. Holds BOTH a machine-readable condition (kind + operator + value) AND the exact 要綱
  # excerpt (raw_text) — that pairing is the crux of grounded assessment. External id: req_….
  #
  # `parent_id` + `logic` are reserved (migration) for a future condition tree
  # ("A かつ B、ただし C を除く"); MVP combines requirements with AND and does NOT evaluate the
  # tree. See RuleCheck for `value` (jsonb) shapes.
  class Requirement < ApplicationRecord
    has_prefix_id :req

    KINDS = %w[income age residence household employment other].freeze
    OPERATORS = %w[lt lte gt gte eq in exists].freeze

    belongs_to :program, class_name: "KyufyCore::Program"
    belongs_to :source_document, class_name: "KyufyCore::SourceDocument", optional: true

    # Reserved for the future condition tree — not evaluated in MVP.
    belongs_to :parent, class_name: "KyufyCore::Requirement", optional: true
    has_many :children, class_name: "KyufyCore::Requirement", foreign_key: :parent_id, dependent: :nullify

    validates :kind, inclusion: { in: KINDS }
    validates :operator, inclusion: { in: OPERATORS }
  end
end
