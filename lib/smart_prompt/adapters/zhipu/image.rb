module SmartPrompt
  module ZhipuAI
    # Text-to-image (CogView / GLM-Image). save_image comes from the ImagePersistence concern.
    module Image
      # Text-to-image. The Zhipu response is NESTED: data.images[].url (not OpenAI's data[]),
      # so we parse defensively. Returns an Array of {url:, b64_json:}.
      def generate_image(prompt, params = {})
        SmartPrompt.logger.info "ZhipuAIAdapter: generating image"
        raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?

        model_name = params[:model] || @config["image_model"] || @config["model"]
        raise Error, "No model configured for image generation" if model_name.nil? || model_name.to_s.strip.empty?

        body = { "model" => model_name, "prompt" => prompt.to_s }
        body["size"]            = params[:size]            if params[:size]
        body["user"]            = params[:user]            if params[:user]
        body["response_format"] = params[:response_format] if params[:response_format]

        SmartPrompt.logger.info "Zhipu image params: #{body.except('prompt').inspect}"
        response =
          begin
            http_post_json(@image_url, body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise Error, "Failed to call Zhipu image generation: #{e.message}"
          end

        images = parse_image_response(response)
        SmartPrompt.logger.info "ZhipuAIAdapter: generated #{images.size} image(s)"
        images
      end

      private

      # Zhipu image response: cogview-3-flash returns the FLAT OpenAI shape data[].url;
      # older docs mention a NESTED data.images[].url. Handle both plus a bare-url array.
      def parse_image_response(response)
        container = response["data"]
        items =
          if container.is_a?(Hash)
            container["images"] || container["data"] || container["url"]
          elsif container.is_a?(Array)
            container
          end
        items ||= response["images"] || response["urls"]

        # Some responses return images as a bare array of URLs (strings).
        items = items.map { |x| x.is_a?(String) ? { "url" => x } : x } if items.is_a?(Array)

        unless items.is_a?(Array) && items.any?
          SmartPrompt.logger.error "Zhipu image response had no images: #{response.inspect}"
          raise LLMAPIError, "No image data in Zhipu response"
        end
        items.map { |d| { url: d["url"], b64_json: d["b64_json"] } }
      end
    end
  end
end
