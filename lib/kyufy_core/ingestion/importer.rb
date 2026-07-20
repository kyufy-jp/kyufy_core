module KyufyCore
  module Ingestion
    # Persists NormalizedProgram -> Program / Requirement / SourceDocument, then chunks each
    # document body and embeds every chunk via the configured embedding adapter (§5).
    class Importer
      # ~200-character windows are plenty for 要綱 excerpts at MVP scale; chunking strategy is
      # an ingestion-time concern the assessment side never sees.
      CHUNK_SIZE = 200

      def initialize(embedding_adapter: KyufyCore.config.embedding_adapter)
        @embedding_adapter = embedding_adapter
      end

      # @param normalized_programs [Array<NormalizedProgram>]
      # @return [Array<KyufyCore::Program>]
      def import(normalized_programs)
        Array(normalized_programs).map { |np| import_one(np) }
      end

      private

      attr_reader :embedding_adapter

      def import_one(np)
        KyufyCore::Program.transaction do
          program = KyufyCore::Program.create!(
            name: np.name,
            authority: np.authority,
            jurisdiction: np.jurisdiction,
            prefecture_code: np.prefecture_code,
            municipality_code: np.municipality_code,
            category: np.category,
            target: np.target,
            official_url: np.official_url,
            valid_from: np.valid_from,
            valid_until: np.valid_until,
            status: np.status || "active"
          )

          documents = Array(np.source_documents).map do |nd|
            create_document(program, nd)
          end

          Array(np.requirements).each do |nr|
            source_document = documents[nr.document_ref] if nr.document_ref
            program.requirements.create!(
              kind: nr.kind,
              operator: nr.operator,
              value: nr.value || {},
              raw_text: nr.raw_text,
              source_document: source_document
            )
          end

          program
        end
      end

      def create_document(program, nd)
        document = program.source_documents.create!(
          title: nd.title,
          url: nd.url,
          body: nd.body,
          fetched_at: nd.fetched_at,
          license: nd.license
        )

        chunk(nd.body).each_with_index do |content, position|
          document.document_chunks.create!(
            content: content,
            position: position,
            embedding: embedding_adapter.embed(content)
          )
        end

        document
      end

      def chunk(body)
        text = body.to_s.strip
        return [] if text.empty?

        text.chars.each_slice(CHUNK_SIZE).map(&:join)
      end
    end
  end
end
