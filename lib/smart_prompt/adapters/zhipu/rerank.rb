module SmartPrompt
  module ZhipuAI
    # Rerank (reorder documents by relevance to a query).
    module Rerank
      def rerank(query, documents, model: nil)
        model_name = model || @config["rerank_model"] || @config["model"]
        body = { "model" => model_name, "query" => query, "documents" => documents }
        response = http_post_json("#{@base_url}/rerank", body)
        (response["results"] || []).map { |r| { index: r["index"], relevance_score: r["relevance_score"] || r["score"] } }
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise LLMAPIError, "Failed to call Zhipu rerank: #{e.message}"
      end
    end
  end
end
