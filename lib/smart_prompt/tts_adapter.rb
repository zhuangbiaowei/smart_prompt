require "openai"
require "base64"
require "net/http"
require "uri"

module SmartPrompt
  class TTSAdapter < LLMAdapter
    # Predefined voice options
    PREDEFINED_VOICES = {
      "alloy" => "沉稳男声alex",
      "echo" => "温柔女声claire",
      "fable" => "活泼女声fable",
      "onyx" => "磁性男声onyx",
      "nova" => "甜美女声nova",
      "shimmer" => "优雅女声shimmer"
    }

    # Supported languages
    SUPPORTED_LANGUAGES = %w[zh en ja ko]

    # Supported output formats
    SUPPORTED_FORMATS = %w[mp3 opus wav pcm]

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
          request_timeout: 120,
        )
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize TTS client: #{e.message}"
        raise LLMAPIError, "Invalid TTS configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize TTS client: #{e.message}"
        raise LLMAPIError, "TTS authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize TTS client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to TTS API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize TTS client: #{e.message}"
        raise Error, "Unexpected error initializing TTS client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully created a TTS client."
      end
    end

    # Text-to-speech synthesis
    def synthesize_speech(text, voice: "alloy", model: nil, speed: 1.0, response_format: "mp3", language: nil)
      SmartPrompt.logger.info "TTSAdapter: Synthesizing speech from text"

      model_name = model || @config["model"]

      # Validate parameters
      validate_tts_parameters(text, voice, speed, response_format, language)

      begin
        # Map voice name if it's a predefined voice
        voice_name = PREDEFINED_VOICES[voice] || voice

        parameters = {
          model: model_name,
          input: text,
          voice: voice_name,
          speed: speed,
          response_format: response_format
        }

        # Add language parameter if specified
        parameters[:language] = language if language

        SmartPrompt.logger.info "TTS parameters: #{parameters.except(:input)}"

        # Custom implementation for TTS since OpenAI gem doesn't support audio endpoints
        response = submit_tts_request(parameters)

        @last_response = response

        # Process response
        if response.is_a?(String) && response.start_with?("data:audio/")
          # Base64 encoded audio data
          audio_data = {
            audio_data: response,
            format: response_format,
            text_length: text.length,
            voice: voice_name
          }

          SmartPrompt.logger.info "TTS synthesis successful, generated #{text.length} characters"
          return audio_data
        else
          SmartPrompt.logger.error "Invalid TTS response format"
          raise LLMAPIError, "Invalid TTS response format"
        end

      rescue OpenAI::Error => e
        SmartPrompt.logger.error "TTS API error: #{e.message}"
        raise LLMAPIError, "TTS API error: #{e.message}"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during TTS synthesis: #{e.message}"
        raise Error, "Unexpected error during TTS synthesis: #{e.message}"
      end
    end

    # Synthesize speech and save to file
    def synthesize_to_file(text, output_path, voice: "alloy", model: nil, speed: 1.0, response_format: "mp3", language: nil)
      SmartPrompt.logger.info "TTSAdapter: Synthesizing speech to file"

      begin
        # Synthesize speech
        audio_data = synthesize_speech(
          text,
          voice: voice,
          model: model,
          speed: speed,
          response_format: response_format,
          language: language
        )

        # Save to file
        save_audio_to_file(audio_data[:audio_data], output_path, response_format)

        SmartPrompt.logger.info "TTS audio saved to: #{output_path}"
        return {
          file_path: output_path,
          text_length: audio_data[:text_length],
          voice: audio_data[:voice],
          format: response_format
        }

      rescue => e
        SmartPrompt.logger.error "Error synthesizing to file: #{e.message}"
        raise Error, "Error synthesizing to file: #{e.message}"
      end
    end

    # Get available voices
    def available_voices
      PREDEFINED_VOICES.dup
    end

    # Create custom voice from reference audio
    def create_custom_voice(name, reference_audio_file, description: nil)
      SmartPrompt.logger.info "TTSAdapter: Creating custom voice"

      begin
        unless File.exist?(reference_audio_file)
          raise Error, "Reference audio file not found: #{reference_audio_file}"
        end

        # Check audio file size (should be less than 30 seconds)
        file_size = File.size(reference_audio_file)
        if file_size > 5 * 1024 * 1024 # 5MB limit
          raise Error, "Reference audio file too large (max 5MB)"
        end

        # Convert audio to base64
        audio_data = File.binread(reference_audio_file)
        base64_audio = Base64.strict_encode64(audio_data)

        parameters = {
          name: name,
          audio: base64_audio
        }

        parameters[:description] = description if description

        SmartPrompt.logger.info "Creating custom voice: #{name}"

        # Custom implementation for voice creation
        response = create_custom_voice_request(parameters)

        @last_response = response

        if response["voice_id"]
          voice_data = {
            voice_id: response["voice_id"],
            name: response["name"],
            status: response["status"],
            created_at: response["created_at"]
          }

          SmartPrompt.logger.info "Custom voice created successfully: #{voice_data[:voice_id]}"
          return voice_data
        else
          SmartPrompt.logger.error "Failed to create custom voice"
          raise LLMAPIError, "Failed to create custom voice"
        end

      rescue => e
        SmartPrompt.logger.error "Error creating custom voice: #{e.message}"
        raise Error, "Error creating custom voice: #{e.message}"
      end
    end

    # List custom voices
    def list_custom_voices
      SmartPrompt.logger.info "TTSAdapter: Listing custom voices"

      begin
        response = list_custom_voices_request

        @last_response = response

        if response["voices"]
          voices = response["voices"].map do |voice|
            {
              voice_id: voice["id"],
              name: voice["name"],
              description: voice["description"],
              status: voice["status"],
              created_at: voice["created_at"]
            }
          end

          SmartPrompt.logger.info "Found #{voices.size} custom voices"
          return voices
        else
          SmartPrompt.logger.error "No custom voices found"
          return []
        end

      rescue => e
        SmartPrompt.logger.error "Error listing custom voices: #{e.message}"
        raise Error, "Error listing custom voices: #{e.message}"
      end
    end

    # Delete custom voice
    def delete_custom_voice(voice_id)
      SmartPrompt.logger.info "TTSAdapter: Deleting custom voice"

      begin
        response = delete_custom_voice_request(voice_id)

        @last_response = response

        if response["deleted"]
          SmartPrompt.logger.info "Custom voice deleted successfully: #{voice_id}"
          return { deleted: true, voice_id: voice_id }
        else
          SmartPrompt.logger.error "Failed to delete custom voice"
          raise LLMAPIError, "Failed to delete custom voice"
        end

      rescue => e
        SmartPrompt.logger.error "Error deleting custom voice: #{e.message}"
        raise Error, "Error deleting custom voice: #{e.message}"
      end
    end

    private

    def validate_tts_parameters(text, voice, speed, response_format, language)
      # Validate text
      if text.nil? || text.strip.empty?
        raise Error, "Text cannot be empty"
      end

      if text.length > 4096
        raise Error, "Text too long (max 4096 characters)"
      end

      # Validate voice
      unless PREDEFINED_VOICES.key?(voice)
        SmartPrompt.logger.warn "Voice '#{voice}' is not a predefined voice, using as custom voice name"
      end

      # Validate speed
      unless (0.25..4.0).include?(speed)
        raise Error, "Speed must be between 0.25 and 4.0"
      end

      # Validate response format
      unless SUPPORTED_FORMATS.include?(response_format)
        raise Error, "Unsupported response format: #{response_format}"
      end

      # Validate language
      if language && !SUPPORTED_LANGUAGES.include?(language)
        raise Error, "Unsupported language: #{language}"
      end
    end

    def save_audio_to_file(audio_data, output_path, format)
      # Create directory if it doesn't exist
      FileUtils.mkdir_p(File.dirname(output_path))

      # Extract base64 data from data URL if present
      if audio_data.start_with?("data:audio/")
        # Remove data URL prefix
        base64_data = audio_data.sub(/^data:audio\/\w+;base64,/, "")
        audio_bytes = Base64.decode64(base64_data)
      else
        # Assume it's already base64
        audio_bytes = Base64.decode64(audio_data)
      end

      # Write to file
      File.binwrite(output_path, audio_bytes)
    end

    # Custom implementation for TTS API call
    def submit_tts_request(parameters)
      uri = URI.parse("#{@config['url']}/audio/speech")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@config['api_key']}"

      request.body = parameters.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        # Return base64 encoded audio data
        "data:audio/#{parameters[:response_format]};base64,#{Base64.strict_encode64(response.body)}"
      else
        raise LLMAPIError, "TTS API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for custom voice creation
    def create_custom_voice_request(parameters)
      uri = URI.parse("#{@config['url']}/voices")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@config['api_key']}"

      request.body = parameters.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "Custom voice creation API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for listing custom voices
    def list_custom_voices_request
      uri = URI.parse("#{@config['url']}/voices")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Authorization'] = "Bearer #{@config['api_key']}"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "List voices API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for deleting custom voice
    def delete_custom_voice_request(voice_id)
      uri = URI.parse("#{@config['url']}/voices/#{voice_id}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Delete.new(uri.request_uri)
      request['Authorization'] = "Bearer #{@config['api_key']}"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "Delete voice API error: #{response.code} - #{response.body}"
      end
    end

    # Override send_request to provide a meaningful error for chat operations
    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.error "TTSAdapter does not support chat operations. Use synthesize_speech or synthesize_to_file methods instead."
      raise NotImplementedError, "TTSAdapter does not support chat operations"
    end

    # Override embeddings method
    def embeddings(text, model)
      SmartPrompt.logger.error "TTSAdapter does not support embeddings operations."
      raise NotImplementedError, "TTSAdapter does not support embeddings operations"
    end
  end
end