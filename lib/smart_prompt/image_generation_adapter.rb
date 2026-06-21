require "openai"
require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"

module SmartPrompt
  # Adapter for SiliconFlow's image generation API.
  #
  # SiliconFlow exposes image generation through a single endpoint:
  #
  #   POST {url}/images/generations
  #
  # Unlike OpenAI's image API, SiliconFlow uses its own parameter names
  # (`image_size`, `batch_size`, `negative_prompt`, `num_inference_steps`,
  # `guidance_scale`, `cfg`, ...) and returns an `images` array instead of a
  # `data` array. The OpenAI gem's `images.generate` helper therefore does not
  # fit, so — like the TTS/Video adapters — we talk to the endpoint directly
  # with Net::HTTP.
  class ImageGenerationAdapter < LLMAdapter
    SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif bmp webp].freeze

    # Default resolution for text-to-image generation ("widthxheight").
    # Edit models (Qwen/Qwen-Image-Edit*) ignore this field, so it is only sent
    # for text-to-image calls.
    DEFAULT_IMAGE_SIZE = "1024x1024"

    def initialize(config)
      super
      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      @api_key  = api_key
      @base_url = @config["url"].to_s.chomp("/")
      @model    = @config["model"]

      begin
        # Created for parity with the other non-chat adapters; the actual image
        # requests are issued directly below via Net::HTTP.
        @client = OpenAI::Client.new(
          access_token: @api_key,
          uri_base: @config["url"],
          request_timeout: 240,
        )
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize ImageGeneration client: #{e.message}"
        raise LLMAPIError, "Invalid ImageGeneration configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize ImageGeneration client: #{e.message}"
        raise LLMAPIError, "ImageGeneration authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize ImageGeneration client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to ImageGeneration API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize ImageGeneration client: #{e.message}"
        raise Error, "Unexpected error initializing ImageGeneration client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully created an ImageGeneration client (model=#{@model})."
      end
    end

    # Text-to-image generation.
    #
    # +params+ accepts SiliconFlow-native keys plus a couple of friendly aliases:
    #
    #   model:, negative_prompt:,
    #   image_size: (alias: size:),
    #   batch_size: (alias: n:),
    #   seed:, num_inference_steps:, guidance_scale:, cfg:
    #
    # Returns an Array of hashes, e.g. [{ url: "...", b64_json: nil, seed: 123 }].
    def generate_image(prompt, params = {})
      SmartPrompt.logger.info "ImageGenerationAdapter: Generating image from text"

      raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?

      parameters = build_parameters(prompt, params)
      parameters[:image_size] = resolve_image_size(params)
      # batch_size only applies to a subset of models (e.g. Kolors); send it
      # only when the caller explicitly asks for it.
      batch = params[:batch_size] || params[:n]
      parameters[:batch_size] = batch if batch

      SmartPrompt.logger.info "Image generation parameters: #{parameters.except(:prompt).inspect}"

      begin
        response = submit_image_request("/images/generations", parameters)
        @last_response = response
        images = parse_images(response)
        SmartPrompt.logger.info "Successfully generated #{images.size} image(s)"
        images
      rescue LLMAPIError, Error
        raise
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse image generation response: #{e.message}"
        raise LLMAPIError, "Failed to parse image generation response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during image generation: #{e.message}"
        raise Error, "Unexpected error during image generation: #{e.message}"
      end
    end

    # Image editing / image-to-image generation (for Qwen/Qwen-Image-Edit-* and
    # Kolors composable models). +image+ (and optionally +image2+/+image3+) may
    # be a local file path, a base64 data URL, or a public http(s) URL.
    def edit_image(prompt, params = {})
      SmartPrompt.logger.info "ImageGenerationAdapter: Editing image"

      raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?
      raise Error, "An input image is required for image editing" if params[:image].nil? && params[:image_file].nil?

      normalized = params.dup
      normalized[:image] = normalize_input_image(normalized[:image] || normalized[:image_file])
      normalized[:image2] = normalize_input_image(normalized[:image2]) if normalized[:image2]
      normalized[:image3] = normalize_input_image(normalized[:image3]) if normalized[:image3]

      # Edit models reject image_size, so we deliberately omit it here.
      parameters = build_parameters(prompt, normalized)
      parameters[:image]  = normalized[:image]
      parameters[:image2] = normalized[:image2] if normalized[:image2]
      parameters[:image3] = normalized[:image3] if normalized[:image3]

      SmartPrompt.logger.info "Image edit parameters: #{parameters.except(:prompt, :image, :image2, :image3).inspect}"

      begin
        response = submit_image_request("/images/generations", parameters)
        @last_response = response
        images = parse_images(response)
        SmartPrompt.logger.info "Successfully edited image, generated #{images.size} result(s)"
        images
      rescue LLMAPIError, Error
        raise
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse image edit response: #{e.message}"
        raise LLMAPIError, "Failed to parse image edit response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during image editing: #{e.message}"
        raise Error, "Unexpected error during image editing: #{e.message}"
      end
    end

    # Save one or many generated images to disk. Accepts the Array returned by
    # #generate_image/#edit_image or a single image hash. Returns the list of
    # written file paths.
    def save_image(image_data, output_dir = "./output", filename_prefix = "generated_image")
      SmartPrompt.logger.info "ImageGenerationAdapter: Saving image to file"

      begin
        FileUtils.mkdir_p(output_dir)
        images = image_data.is_a?(Array) ? image_data : [image_data]

        saved_files = images.each_with_index.map do |img, index|
          save_single_image(img, output_dir, "#{filename_prefix}_#{index + 1}")
        end

        SmartPrompt.logger.info "Successfully saved #{saved_files.size} image(s) to #{output_dir}"
        saved_files
      rescue => e
        SmartPrompt.logger.error "Error saving image: #{e.message}"
        raise Error, "Error saving image: #{e.message}"
      end
    end

    private

    # Assemble the common SiliconFlow request parameters (everything except the
    # text-vs-image specific fields handled by the callers).
    def build_parameters(prompt, params)
      model_name = params[:model] || @model
      if model_name.nil? || model_name.to_s.strip.empty?
        raise Error, "No model configured for image generation (set llm 'model' or pass model:)"
      end

      parameters = { model: model_name, prompt: prompt.to_s }
      parameters[:negative_prompt]     = params[:negative_prompt]     if params[:negative_prompt]
      parameters[:seed]                = params[:seed]                if params[:seed]
      parameters[:num_inference_steps] = params[:num_inference_steps] if params[:num_inference_steps]
      parameters[:guidance_scale]      = params[:guidance_scale]      if params[:guidance_scale]
      parameters[:cfg]                 = params[:cfg]                 if params[:cfg]
      parameters
    end

    def resolve_image_size(params)
      size = params[:image_size] || params[:size]
      size.nil? || size.to_s.strip.empty? ? DEFAULT_IMAGE_SIZE : size.to_s
    end

    # POST a JSON body to the given SiliconFlow path and return the parsed
    # response hash, raising LLMAPIError on non-2xx responses.
    def submit_image_request(path, parameters)
      uri = URI.parse("#{@base_url}#{path}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 240

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request.body = parameters.to_json

      SmartPrompt.logger.debug "Image request POST #{uri} body=#{parameters.to_json}"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        SmartPrompt.logger.error "Image API error: #{response.code} - #{response.body}"
        raise LLMAPIError, "Image generation API error: #{response.code} - #{response.body}"
      end
    end

    # Normalize the SiliconFlow `images` response into a uniform Array of
    # symbol-keyed hashes. Falls back to OpenAI's `data` key for compatibility.
    def parse_images(response)
      items = response["images"] || response["data"]
      items = [] unless items.is_a?(Array)

      if items.empty?
        SmartPrompt.logger.error "No image data in response: #{response.inspect}"
        raise LLMAPIError, "No image data in response"
      end

      items.map do |image_data|
        {
          url: image_data["url"],
          b64_json: image_data["b64_json"],
          seed: image_data["seed"],
        }
      end
    end

    # Accept a local file path, a base64 data URL, or an http(s) URL and return
    # the value SiliconFlow expects in the `image` field.
    def normalize_input_image(image)
      return image if image.nil?

      if image.is_a?(String)
        return image if image.start_with?("data:")
        return image if image.start_with?("http://", "https://")
      end

      raise Error, "Image file not found: #{image}" unless File.exist?(image)

      ext = File.extname(image).downcase.delete(".")
      unless SUPPORTED_IMAGE_FORMATS.include?(ext)
        raise Error, "Unsupported image format: #{ext}"
      end

      mime = ext == "jpg" ? "jpeg" : ext
      "data:image/#{mime};base64,#{Base64.strict_encode64(File.binread(image))}"
    end

    def save_single_image(image_data, output_dir, filename)
      if image_data[:b64_json]
        file_path = File.join(output_dir, "#{filename}.png")
        File.binwrite(file_path, Base64.decode64(image_data[:b64_json]))
      elsif image_data[:url]
        uri = URI.parse(image_data[:url])
        response = Net::HTTP.get_response(uri)

        raise Error, "Failed to download image from URL: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        ext = case response["content-type"]
              when "image/jpeg", "image/jpg" then "jpg"
              when "image/png" then "png"
              when "image/gif" then "gif"
              when "image/webp" then "webp"
              else "png"
              end

        file_path = File.join(output_dir, "#{filename}.#{ext}")
        File.binwrite(file_path, response.body)
      else
        raise Error, "No image data available to save"
      end

      file_path
    end

    # Override send_request to provide a meaningful error for chat operations.
    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.error "ImageGenerationAdapter does not support chat operations. Use generate_image or edit_image instead."
      raise NotImplementedError, "ImageGenerationAdapter does not support chat operations"
    end

    # Override embeddings method.
    def embeddings(text, model)
      SmartPrompt.logger.error "ImageGenerationAdapter does not support embeddings operations."
      raise NotImplementedError, "ImageGenerationAdapter does not support embeddings operations"
    end
  end
end
