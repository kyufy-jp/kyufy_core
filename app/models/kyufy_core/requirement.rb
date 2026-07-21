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

    # Japanese label per kind. `kind` is an English enum (machine-readable), but it is also
    # spoken aloud in user-facing Japanese prose — explanations, verdict cards — where a bare
    # "income" reads as broken Japanese. Canonical here, next to KINDS, so hosts and adapters
    # share one vocabulary instead of each inventing its own map.
    KIND_LABELS = {
      "income" => "所得",
      "age" => "年齢",
      "residence" => "居住地",
      "household" => "世帯",
      "employment" => "就労",
      "other" => "その他"
    }.freeze

    # Japanese label for a kind (String or Symbol). Falls back to the raw value so an
    # unrecognized kind degrades to something visible rather than nil.
    def self.kind_label(kind)
      KIND_LABELS.fetch(kind.to_s, kind.to_s)
    end

    belongs_to :program, class_name: "KyufyCore::Program"
    belongs_to :source_document, class_name: "KyufyCore::SourceDocument", optional: true

    # Reserved for the future condition tree — not evaluated in MVP.
    belongs_to :parent, class_name: "KyufyCore::Requirement", optional: true
    has_many :children, class_name: "KyufyCore::Requirement", foreign_key: :parent_id, dependent: :nullify

    validates :kind, inclusion: { in: KINDS }
    validates :operator, inclusion: { in: OPERATORS }
  end
end
