module SmartPrompt
  module SiliconFlow
    # Embeddings (BAAI/bge-m3 default; Qwen3-Embedding supports custom dimensions).
    module Embed
      # BAAI/bge-m3 (default, fixed 1024 dims) or Qwen3-Embedding (custom dimensions).
      # `dimensions` is only honored when set in config (Qwen3-Embedding series only).
      # Returns the first embedding vector.
      def embeddings(text, model)
        model_name = model || @config["embedding_model"] || @config["model"]
        SmartPrompt.logger.info "SiliconFlowAdapter: embeddings model=#{model_name}"

        body = { "model" => model_name, "input" => text.is_a?(Array) ? text : [text.to_s] }
        body["dimensions"] = @config["dimensions"] if @config["dimensions"]
        body["encoding_format"] = @config["encoding_format"] if @config["encoding_format"]

        response =
          begin
            http_post_json("#{@base_url}/embeddings", body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise LLMAPIError, "Failed to call SiliconFlow embeddings: #{e.message}"
          end

        items = response["data"]
        unless items.is_a?(Array) && items.any? && items[0]["embedding"]
          raise LLMAPIError, "No embedding vector in SiliconFlow response: #{response.inspect}"
        end
        items[0]["embedding"]
      end
    end
  end
end
