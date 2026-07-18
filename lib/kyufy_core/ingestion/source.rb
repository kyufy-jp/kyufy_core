module KyufyCore
  module Ingestion
    # Abstract source port (§5). Concrete adapters (per municipality / format) live OUTSIDE
    # this gem and implement #fetch_programs, returning normalized programs. The engine never
    # branches on a municipality — all format/wording variance is absorbed here, once.
    class Source
      # @return [Array<NormalizedProgram>]
      def fetch_programs
        raise NotImplementedError, "#{self.class} must implement #fetch_programs"
      end
    end
  end
end
