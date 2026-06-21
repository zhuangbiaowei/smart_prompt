require "openai"
require "base64"

module SmartPrompt
  class MultimodalAdapter < LLMAdapter
    SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif bmp webp]
    SUPPORTED_VIDEO_FORMATS = %w[mp4 mov avi mkv webm]

    def initialize(config)
      super
      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      begin
        @client = OpenAI::Client.new(
          access_token: api_key,
          uri_base: @config["url"],
          request_timeout: 240,
        )
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize Multimodal client: #{e.message}"
        raise LLMAPIError, "Invalid Multimodal configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize Multimodal client: #{e.message}"
        raise LLMAPIError, "Multimodal authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize Multimodal client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to Multimodal API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize Multimodal client: #{e.message}"
        raise Error, "Unexpected error initializing Multimodal client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully created a Multimodal client."
      end
    end

    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.info "MultimodalAdapter: Sending multimodal request"

      # Process messages to handle multimodal content
      processed_messages = process_multimodal_messages(messages)

      temperature = 0.7 if temperature.nil?
      model_name = model || @config["model"]

      SmartPrompt.logger.info "MultimodalAdapter: Using model #{model_name}"

      begin
        parameters = {
          model: model_name,
          messages: processed_messages,
          temperature: @config["temperature"] || temperature,
        }

        if proc
          parameters[:stream] = proc
        end

        if tools
          parameters[:tools] = tools
        end

        SmartPrompt.logger.info "Send parameters is: #{parameters}"
        response = @client.chat(parameters: parameters)

      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Multimodal API error: #{e.message}"
        raise LLMAPIError, "Multimodal API error: #{e.message}"
      rescue OpenAI::MiddlewareErrors => e
        SmartPrompt.logger.error "Multimodal HTTP Error: #{e.message}"
        raise LLMAPIError, "Multimodal HTTP Error"
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse Multimodal API response"
        raise LLMAPIError, "Failed to parse Multimodal API response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during Multimodal request: #{e.message}"
        raise Error, "Unexpected error during Multimodal request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully sent multimodal message"
      end

      SmartPrompt.logger.info "MultimodalAdapter: Received response from Multimodal API"

      if proc.nil?
        @last_response = response
        return response.dig("choices", 0, "message", "content")
      end
    end

    # Analyze image with text prompt
    def analyze_image(image_input, prompt, model = nil, detail: "auto", max_tokens: nil)
      SmartPrompt.logger.info "MultimodalAdapter: Analyzing image"

      messages = [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "image_url", image_url: prepare_image_input(image_input, detail) }
          ]
        }
      ]

      model_name = model || @config["model"]
      parameters = {
        model: model_name,
        messages: messages,
        temperature: @config["temperature"] || 0.7,
      }

      parameters[:max_tokens] = max_tokens if max_tokens

      response = @client.chat(parameters: parameters)
      @last_response = response
      response.dig("choices", 0, "message", "content")
    end

    # Analyze video with text prompt
    def analyze_video(video_input, prompt, model = nil, max_frames: 10, fps: 1, detail: "auto")
      SmartPrompt.logger.info "MultimodalAdapter: Analyzing video"

      messages = [
        {
          role: "user",
          content: [
            { type: "text", text: prompt },
            { type: "video_url", video_url: prepare_video_input(video_input, max_frames, fps, detail) }
          ]
        }
      ]

      model_name = model || @config["model"]
      response = @client.chat(parameters: {
        model: model_name,
        messages: messages,
        temperature: @config["temperature"] || 0.7,
      })

      @last_response = response
      response.dig("choices", 0, "message", "content")
    end

    # Multi-image analysis
    def analyze_multiple_images(images, prompt, model = nil, detail: "auto")
      SmartPrompt.logger.info "MultimodalAdapter: Analyzing multiple images"

      content = [{ type: "text", text: prompt }]
      images.each do |image_input|
        content << { type: "image_url", image_url: prepare_image_input(image_input, detail) }
      end

      messages = [{ role: "user", content: content }]

      model_name = model || @config["model"]
      response = @client.chat(parameters: {
        model: model_name,
        messages: messages,
        temperature: @config["temperature"] || 0.7,
      })

      @last_response = response
      response.dig("choices", 0, "message", "content")
    end

    private

    def process_multimodal_messages(messages)
      messages.map do |message|
        if message[:content].is_a?(Array)
          # Process content array with multimodal elements
          processed_content = message[:content].map do |content_item|
            if content_item.is_a?(Hash)
              case content_item[:type]
              when "image_url"
                { type: "image_url", image_url: prepare_image_input(content_item[:image_url], content_item[:detail]) }
              when "video_url"
                { type: "video_url", video_url: prepare_video_input(content_item[:video_url], content_item[:max_frames], content_item[:fps], content_item[:detail]) }
              else
                content_item
              end
            else
              { type: "text", text: content_item.to_s }
            end
          end
          { role: message[:role], content: processed_content }
        else
          message
        end
      end
    end

    def prepare_image_input(image_input, detail = "auto")
      detail ||= "auto"

      case image_input
      when String
        if image_input.start_with?("http://", "https://")
          { url: image_input, detail: detail }
        elsif File.exist?(image_input)
          # Convert local file to base64
          file_ext = File.extname(image_input).downcase.delete(".")
          unless SUPPORTED_IMAGE_FORMATS.include?(file_ext)
            raise Error, "Unsupported image format: #{file_ext}"
          end

          image_data = File.binread(image_input)
          base64_data = Base64.strict_encode64(image_data)
          mime_type = "image/#{file_ext == 'jpg' ? 'jpeg' : file_ext}"

          { url: "data:#{mime_type};base64,#{base64_data}", detail: detail }
        else
          raise Error, "Invalid image input: #{image_input}"
        end
      when Hash
        # Assume it's already formatted
        image_input[:detail] ||= detail
        image_input
      else
        raise Error, "Unsupported image input type: #{image_input.class}"
      end
    end

    def prepare_video_input(video_input, max_frames = 10, fps = 1, detail = "auto")
      max_frames ||= 10
      fps ||= 1
      detail ||= "auto"

      case video_input
      when String
        if video_input.start_with?("http://", "https://")
          {
            url: video_input,
            detail: detail,
            max_frames: max_frames,
            fps: fps
          }
        elsif File.exist?(video_input)
          # For local files, we'd need to upload or convert
          # Currently only support URLs for videos
          raise Error, "Local video files not yet supported. Please provide a URL."
        else
          raise Error, "Invalid video input: #{video_input}"
        end
      when Hash
        # Assume it's already formatted
        video_input[:max_frames] ||= max_frames
        video_input[:fps] ||= fps
        video_input[:detail] ||= detail
        video_input
      else
        raise Error, "Unsupported video input type: #{video_input.class}"
      end
    end

    def embeddings(text, model)
      SmartPrompt.logger.info "MultimodalAdapter: Getting embeddings"

      model_name = model || @config["model"]
      begin
        response = @client.embeddings(
          parameters: {
            model: model_name,
            input: text.to_s,
          },
        )
      rescue => e
        SmartPrompt.logger.error "Unexpected error during embeddings request: #{e.message}"
        raise Error, "Unexpected error during embeddings request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully got embeddings"
      end

      response.dig("data", 0, "embedding")
    end
  end
end