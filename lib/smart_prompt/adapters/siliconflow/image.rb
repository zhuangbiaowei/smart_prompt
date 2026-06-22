module SmartPrompt
  module SiliconFlow
    # Text-to-image (Kolors) + image editing (Qwen-Image-Edit). save_image comes from
    # the ImagePersistence concern.
    module Image
      # Default resolution for text-to-image (Kolors accepts these "WxH" values).
      DEFAULT_IMAGE_SIZE = "1024x1024".freeze

      # Text-to-image. SiliconFlow response is images[].url (not OpenAI's data[]),
      # and uses its own param names (image_size, batch_size, guidance_scale, ...).
      # Returns an Array of {url:, b64_json:, seed:}.
      def generate_image(prompt, params = {})
        SmartPrompt.logger.info "SiliconFlowAdapter: generating image"
        raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?

        model_name = params[:model] || @config["image_model"] || @config["model"]
        raise Error, "No model configured for image generation" if model_name.nil? || model_name.to_s.strip.empty?

        body = { "model" => model_name, "prompt" => prompt.to_s }
        body["image_size"]          = resolve_image_size(params[:image_size] || params[:size])
        body["negative_prompt"]     = params[:negative_prompt]     if params[:negative_prompt]
        body["seed"]                = params[:seed]                if params[:seed]
        body["num_inference_steps"] = params[:num_inference_steps] if params[:num_inference_steps]
        body["guidance_scale"]      = params[:guidance_scale]      if params[:guidance_scale]
        # batch_size only applies to a subset of models (e.g. Kolors); send it only
        # when the caller explicitly asks for it.
        batch = params[:batch_size] || params[:n]
        body["batch_size"] = batch if batch

        SmartPrompt.logger.info "SiliconFlow image params: #{body.except('prompt').inspect}"
        response =
          begin
            http_post_json(@image_url, body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise Error, "Failed to call SiliconFlow image generation: #{e.message}"
          end

        images = parse_image_response(response)
        SmartPrompt.logger.info "SiliconFlowAdapter: generated #{images.size} image(s)"
        images
      end

      # Image editing / image-to-image (Qwen/Qwen-Image-Edit-2509 and Kolors composable).
      # +image+ (and optionally +image2+/+image3+) may be a local file path, a base64
      # data URL, or a public http(s) URL. Edit models reject image_size, so we omit it.
      def edit_image(prompt, params = {})
        SmartPrompt.logger.info "SiliconFlowAdapter: editing image"
        raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?
        raise Error, "An input image is required for image editing" if params[:image].nil? && params[:image_file].nil?

        model_name = params[:model] || @config["image_model"] || @config["model"]
        raise Error, "No model configured for image generation" if model_name.nil? || model_name.to_s.strip.empty?

        body = { "model" => model_name, "prompt" => prompt.to_s }
        body["image"]          = normalize_input_image(params[:image] || params[:image_file])
        body["image2"]         = normalize_input_image(params[:image2]) if params[:image2]
        body["image3"]         = normalize_input_image(params[:image3]) if params[:image3]
        body["negative_prompt"] = params[:negative_prompt] if params[:negative_prompt]
        body["seed"]           = params[:seed]            if params[:seed]
        body["guidance_scale"] = params[:guidance_scale]  if params[:guidance_scale]

        SmartPrompt.logger.info "SiliconFlow image edit params: #{body.except('prompt', 'image', 'image2', 'image3').inspect}"
        response =
          begin
            http_post_json(@image_url, body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise Error, "Failed to call SiliconFlow image edit: #{e.message}"
          end

        images = parse_image_response(response)
        SmartPrompt.logger.info "SiliconFlowAdapter: edited into #{images.size} image(s)"
        images
      end

      private

      # SiliconFlow image response: images[].url (FLAT). Fall back to OpenAI's
      # data[] or a bare-url array for defensive compatibility.
      def parse_image_response(response)
        items = response["images"] || response["data"]
        items = [] unless items.is_a?(Array)
        if items.empty?
          SmartPrompt.logger.error "No image data in SiliconFlow response: #{response.inspect}"
          raise LLMAPIError, "No image data in SiliconFlow response"
        end
        items.map do |d|
          d = { "url" => d } if d.is_a?(String)
          { url: d["url"], b64_json: d["b64_json"], seed: d["seed"] }
        end
      end

      # Resolve the image size: default 1024x1024 when none given.
      def resolve_image_size(size)
        return DEFAULT_IMAGE_SIZE if size.nil? || size.to_s.strip.empty?
        size.to_s
      end
    end
  end
end
