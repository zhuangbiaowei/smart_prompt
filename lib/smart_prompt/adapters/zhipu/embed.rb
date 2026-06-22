module SmartPrompt
  module ZhipuAI
    # Embeddings (embedding-3, custom dimensions).
    module Embed
      # embedding-3 (default 2048 dims); supports a custom `dimensions` (256/512/1024/2048)
      # via config. Returns the first embedding vector.
      def embeddings(text, model)
        model_name = model || @config["embedding_model"] || @config["model"]
        SmartPrompt.logger.info "ZhipuAIAdapter: embeddings model=#{model_name}"

        body = { "model" => model_name, "input" => text.is_a?(Array) ? text : [text.to_s] }
        body["dimensions"] = @config["dimensions"] if @config["dimensions"]
        body["encoding_format"] = @config["encoding_format"] if @config["encoding_format"]

        response =
          begin
            http_post_json("#{@base_url}/embeddings", body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise LLMAPIError, "Failed to call Zhipu embeddings: #{e.message}"
          end

        items = response["data"]
        unless items.is_a?(Array) && items.any? && items[0]["embedding"]
          raise LLMAPIError, "No embedding vector in Zhipu response: #{response.inspect}"
        end
        items[0]["embedding"]
      end
    end
  end
end
