module SmartPrompt
  module SiliconFlow
    # Rerank (reorder documents by relevance to a query).
    module Rerank
      # Reorder documents by relevance to a query. SiliconFlow returns
      # results[].relevance_score (NOT "score"). Returns an Array of
      # {index:, relevance_score:} sorted by the provider.
      def rerank(query, documents, model: nil, **opts)
        model_name = model || @config["rerank_model"] || @config["model"]
        SmartPrompt.logger.info "SiliconFlowAdapter: rerank model=#{model_name}"

        body = { "model" => model_name, "query" => query.to_s, "documents" => documents }
        body["top_n"]                = opts[:top_n]                if opts[:top_n]
        body["return_documents"]     = opts[:return_documents]     unless opts[:return_documents].nil?
        body["max_chunks_per_doc"]   = opts[:max_chunks_per_doc]   if opts[:max_chunks_per_doc]
        body["chunk_overlap_tokens"] = opts[:chunk_overlap_tokens] if opts[:chunk_overlap_tokens]
        body["instruction"]          = opts[:instruction]          if opts[:instruction]

        response =
          begin
            http_post_json("#{@base_url}/rerank", body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise LLMAPIError, "Failed to call SiliconFlow rerank: #{e.message}"
          end

        parse_rerank_response(response)
      end

      private

      # SiliconFlow rerank response: results[].relevance_score (NOT "score").
      def parse_rerank_response(response)
        (response["results"] || []).map do |r|
          { index: r["index"], relevance_score: r["relevance_score"] || r["score"] }
        end
      end
    end
  end
end
