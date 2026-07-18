module KyufyCore
  # 要綱 source text. fetched_at + url model attribution & freshness. External id: doc_….
  class SourceDocument < ApplicationRecord
    has_prefix_id :doc

    belongs_to :program, class_name: "KyufyCore::Program"
    has_many :requirements, class_name: "KyufyCore::Requirement", dependent: :nullify
    has_many :document_chunks, class_name: "KyufyCore::DocumentChunk", dependent: :destroy

    validates :title, presence: true
  end
end
