require "openai"
require "base64"
require "net/http"
require "uri"

module SmartPrompt
  class STTAdapter < LLMAdapter
    # Supported audio formats
    SUPPORTED_AUDIO_FORMATS = %w[mp3 mp4 mpeg mpga m4a wav webm]

    # Supported languages for speech recognition
    SUPPORTED_LANGUAGES = %w[zh en ja ko]

    # Maximum file size (25MB)
    MAX_FILE_SIZE = 25 * 1024 * 1024

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
        SmartPrompt.logger.error "Failed to initialize STT client: #{e.message}"
        raise LLMAPIError, "Invalid STT configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize STT client: #{e.message}"
        raise LLMAPIError, "STT authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize STT client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to STT API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize STT client: #{e.message}"
        raise Error, "Unexpected error initializing STT client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully created an STT client."
      end
    end

    # Speech-to-text transcription
    def transcribe_audio(audio_file, model: nil, language: nil, prompt: nil, temperature: 0.0, response_format: "json")
      SmartPrompt.logger.info "STTAdapter: Transcribing audio to text"

      model_name = model || @config["model"]

      # Validate parameters
      validate_stt_parameters(audio_file, language, response_format)

      begin
        # Prepare audio file
        audio_data = prepare_audio_file(audio_file)

        parameters = {
          model: model_name,
          file: audio_data[:file],
          temperature: temperature,
          response_format: response_format
        }

        # Add optional parameters
        parameters[:language] = language if language
        parameters[:prompt] = prompt if prompt

        SmartPrompt.logger.info "STT parameters: #{parameters.except(:file)}"

        # Custom implementation for STT since OpenAI gem doesn't support audio transcription endpoints
        response = submit_stt_request(parameters)

        @last_response = response

        # Process response
        if response["text"]
          transcription_data = {
            text: response["text"],
            language: language,
            duration: audio_data[:duration],
            file_size: audio_data[:file_size],
            format: audio_data[:format]
          }

          SmartPrompt.logger.info "STT transcription successful, transcribed #{response['text'].length} characters"
          return transcription_data
        else
          SmartPrompt.logger.error "No text in STT response"
          raise LLMAPIError, "No text in STT response"
        end

      rescue OpenAI::Error => e
        SmartPrompt.logger.error "STT API error: #{e.message}"
        raise LLMAPIError, "STT API error: #{e.message}"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during STT transcription: #{e.message}"
        raise Error, "Unexpected error during STT transcription: #{e.message}"
      end
    end

    # Transcribe audio from URL
    def transcribe_audio_url(audio_url, model: nil, language: nil, prompt: nil, temperature: 0.0, response_format: "json")
      SmartPrompt.logger.info "STTAdapter: Transcribing audio from URL"

      model_name = model || @config["model"]

      begin
        parameters = {
          model: model_name,
          audio_url: audio_url,
          temperature: temperature,
          response_format: response_format
        }

        # Add optional parameters
        parameters[:language] = language if language
        parameters[:prompt] = prompt if prompt

        SmartPrompt.logger.info "STT URL parameters: #{parameters}"

        # Custom implementation for URL-based STT
        response = submit_stt_url_request(parameters)

        @last_response = response

        if response["text"]
          transcription_data = {
            text: response["text"],
            language: language,
            audio_url: audio_url
          }

          SmartPrompt.logger.info "STT URL transcription successful, transcribed #{response['text'].length} characters"
          return transcription_data
        else
          SmartPrompt.logger.error "No text in STT URL response"
          raise LLMAPIError, "No text in STT URL response"
        end

      rescue => e
        SmartPrompt.logger.error "Error in URL transcription: #{e.message}"
        raise Error, "Error in URL transcription: #{e.message}"
      end
    end

    # Batch transcription
    def transcribe_batch(audio_files, model: nil, language: nil, prompt: nil, temperature: 0.0)
      SmartPrompt.logger.info "STTAdapter: Batch transcribing #{audio_files.size} audio files"

      results = []

      audio_files.each_with_index do |audio_file, index|
        begin
          SmartPrompt.logger.info "Transcribing file #{index + 1}/#{audio_files.size}: #{File.basename(audio_file)}"

          result = transcribe_audio(
            audio_file,
            model: model,
            language: language,
            prompt: prompt,
            temperature: temperature
          )

          results << {
            file: audio_file,
            index: index,
            transcription: result,
            success: true
          }

        rescue => e
          SmartPrompt.logger.error "Failed to transcribe #{audio_file}: #{e.message}"
          results << {
            file: audio_file,
            index: index,
            error: e.message,
            success: false
          }
        end
      end

      {
        total_files: audio_files.size,
        successful: results.count { |r| r[:success] },
        failed: results.count { |r| !r[:success] },
        results: results
      }
    end

    # Get audio file information
    def get_audio_info(audio_file)
      SmartPrompt.logger.info "STTAdapter: Getting audio file information"

      begin
        unless File.exist?(audio_file)
          raise Error, "Audio file not found: #{audio_file}"
        end

        file_ext = File.extname(audio_file).downcase.delete(".")
        unless SUPPORTED_AUDIO_FORMATS.include?(file_ext)
          raise Error, "Unsupported audio format: #{file_ext}"
        end

        file_size = File.size(audio_file)
        if file_size > MAX_FILE_SIZE
          raise Error, "Audio file too large (max #{MAX_FILE_SIZE / (1024 * 1024)}MB)"
        end

        # Estimate duration (rough calculation)
        # Note: This is a simplified estimation, actual duration may vary
        duration = estimate_audio_duration(file_size, file_ext)

        {
          file_path: audio_file,
          file_name: File.basename(audio_file),
          file_size: file_size,
          format: file_ext,
          estimated_duration: duration,
          supported: true
        }

      rescue => e
        SmartPrompt.logger.error "Error getting audio info: #{e.message}"
        raise Error, "Error getting audio info: #{e.message}"
      end
    end

    # Language detection (basic implementation)
    def detect_language(text)
      SmartPrompt.logger.info "STTAdapter: Detecting language from text"

      # Simple language detection based on character ranges
      if text =~ /[\u4e00-\u9fff]/
        "zh"
      elsif text =~ /[\u3040-\u309f\u30a0-\u30ff]/
        "ja"
      elsif text =~ /[\uac00-\ud7af]/
        "ko"
      else
        "en"
      end
    end

    private

    def validate_stt_parameters(audio_file, language, response_format)
      # Validate audio file
      unless File.exist?(audio_file)
        raise Error, "Audio file not found: #{audio_file}"
      end

      file_ext = File.extname(audio_file).downcase.delete(".")
      unless SUPPORTED_AUDIO_FORMATS.include?(file_ext)
        raise Error, "Unsupported audio format: #{file_ext}"
      end

      file_size = File.size(audio_file)
      if file_size > MAX_FILE_SIZE
        raise Error, "Audio file too large (max #{MAX_FILE_SIZE / (1024 * 1024)}MB)"
      end

      # Validate language
      if language && !SUPPORTED_LANGUAGES.include?(language)
        raise Error, "Unsupported language: #{language}"
      end

      # Validate response format
      unless %w[json text srt vtt].include?(response_format)
        raise Error, "Unsupported response format: #{response_format}"
      end
    end

    def prepare_audio_file(audio_file)
      file_ext = File.extname(audio_file).downcase.delete(".")
      file_size = File.size(audio_file)
      duration = estimate_audio_duration(file_size, file_ext)

      {
        file: File.open(audio_file, "rb"),
        format: file_ext,
        file_size: file_size,
        duration: duration
      }
    end

    def estimate_audio_duration(file_size, format)
      # Rough estimation based on format and file size
      # These are approximate values and may vary
      case format
      when "mp3", "m4a"
        # Average bitrate ~128kbps
        (file_size * 8) / (128 * 1024) # Convert to seconds
      when "wav"
        # WAV files are larger, estimate based on CD quality
        (file_size / (44100 * 2 * 2)).to_i # 44.1kHz, 16-bit, stereo
      when "webm"
        # Variable bitrate, rough estimate
        (file_size * 8) / (96 * 1024) # ~96kbps
      else
        # Default estimation
        (file_size * 8) / (128 * 1024)
      end
    end

    # Custom implementation for STT API call
    def submit_stt_request(parameters)
      uri = URI.parse("#{@config['url']}/audio/transcriptions")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      # Create multipart form data
      boundary = "----WebKitFormBoundary#{Time.now.to_i}"

      body = ""
      body << "--#{boundary}\r\n"
      body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(parameters[:file].path)}\"\r\n"
      body << "Content-Type: audio/#{File.extname(parameters[:file].path).delete('.')}\r\n\r\n"
      body << parameters[:file].read
      body << "\r\n"

      # Add other parameters
      parameters.except(:file).each do |key, value|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"#{key}\"\r\n\r\n"
        body << "#{value}\r\n"
      end

      body << "--#{boundary}--\r\n"

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"
      request['Authorization'] = "Bearer #{@config['api_key']}"
      request.body = body

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "STT API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for URL-based STT
    def submit_stt_url_request(parameters)
      uri = URI.parse("#{@config['url']}/audio/transcriptions")

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
        raise LLMAPIError, "STT URL API error: #{response.code} - #{response.body}"
      end
    end

    # Override send_request to provide a meaningful error for chat operations
    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.error "STTAdapter does not support chat operations. Use transcribe_audio or transcribe_audio_url methods instead."
      raise NotImplementedError, "STTAdapter does not support chat operations"
    end

    # Override embeddings method
    def embeddings(text, model)
      SmartPrompt.logger.error "STTAdapter does not support embeddings operations."
      raise NotImplementedError, "STTAdapter does not support embeddings operations"
    end
  end
end