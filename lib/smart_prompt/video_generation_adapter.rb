require "openai"
require "base64"
require "net/http"
require "uri"

module SmartPrompt
  class VideoGenerationAdapter < LLMAdapter
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
          request_timeout: 600, # Longer timeout for video generation
        )
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize VideoGeneration client: #{e.message}"
        raise LLMAPIError, "Invalid VideoGeneration configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize VideoGeneration client: #{e.message}"
        raise LLMAPIError, "VideoGeneration authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize VideoGeneration client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to VideoGeneration API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize VideoGeneration client: #{e.message}"
        raise Error, "Unexpected error initializing VideoGeneration client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successfully created a VideoGeneration client."
      end
    end

    # Text-to-video generation
    def generate_video(prompt, model: nil, duration: 4, resolution: "720p", fps: 24, seed: nil)
      SmartPrompt.logger.info "VideoGenerationAdapter: Generating video from text"

      model_name = model || @config["model"]

      begin
        # SiliconFlow uses OpenAI-compatible API format for video generation
        # Note: This might require custom implementation as OpenAI gem doesn't have video endpoints
        parameters = {
          model: model_name,
          prompt: prompt,
          duration: duration,
          resolution: resolution,
          fps: fps
        }

        parameters[:seed] = seed if seed

        SmartPrompt.logger.info "Video generation parameters: #{parameters}"

        # Custom implementation for video generation
        # Since OpenAI gem doesn't support video endpoints, we'll use direct HTTP calls
        response = submit_video_generation_request(parameters)

        @last_response = response

        # Process response
        if response["data"] && response["data"]["video_url"]
          video_data = {
            video_url: response["data"]["video_url"],
            status: response["data"]["status"],
            job_id: response["data"]["id"],
            created_at: response["data"]["created_at"]
          }

          SmartPrompt.logger.info "Video generation job submitted successfully"
          return video_data
        else
          SmartPrompt.logger.error "No video data in response"
          raise LLMAPIError, "No video data in response"
        end

      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Video generation API error: #{e.message}"
        raise LLMAPIError, "Video generation API error: #{e.message}"
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse video generation response"
        raise LLMAPIError, "Failed to parse video generation response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during video generation: #{e.message}"
        raise Error, "Unexpected error during video generation: #{e.message}"
      end
    end

    # Image-to-video generation
    def create_video_from_image(image_file, prompt, model: nil, duration: 4, resolution: "720p", fps: 24, seed: nil)
      SmartPrompt.logger.info "VideoGenerationAdapter: Creating video from image"

      model_name = model || @config["model"]

      begin
        # Prepare image file
        unless File.exist?(image_file)
          raise Error, "Image file not found: #{image_file}"
        end

        file_ext = File.extname(image_file).downcase.delete(".")
        unless SUPPORTED_IMAGE_FORMATS.include?(file_ext)
          raise Error, "Unsupported image format: #{file_ext}"
        end

        # Convert image to base64 for API submission
        image_data = File.binread(image_file)
        base64_image = Base64.strict_encode64(image_data)

        parameters = {
          model: model_name,
          image: base64_image,
          prompt: prompt,
          duration: duration,
          resolution: resolution,
          fps: fps
        }

        parameters[:seed] = seed if seed

        SmartPrompt.logger.info "Image-to-video parameters: #{parameters}"

        # Custom implementation for image-to-video generation
        response = submit_image_to_video_request(parameters)

        @last_response = response

        if response["data"] && response["data"]["video_url"]
          video_data = {
            video_url: response["data"]["video_url"],
            status: response["data"]["status"],
            job_id: response["data"]["id"],
            created_at: response["data"]["created_at"]
          }

          SmartPrompt.logger.info "Image-to-video job submitted successfully"
          return video_data
        else
          SmartPrompt.logger.error "No video data in image-to-video response"
          raise LLMAPIError, "No video data in image-to-video response"
        end

      rescue => e
        SmartPrompt.logger.error "Unexpected error during image-to-video generation: #{e.message}"
        raise Error, "Unexpected error during image-to-video generation: #{e.message}"
      end
    end

    # Check video generation status
    def check_video_status(job_id)
      SmartPrompt.logger.info "VideoGenerationAdapter: Checking video generation status"

      begin
        response = check_video_generation_status(job_id)

        @last_response = response

        if response["data"]
          status_data = {
            job_id: response["data"]["id"],
            status: response["data"]["status"],
            video_url: response["data"]["video_url"],
            progress: response["data"]["progress"],
            created_at: response["data"]["created_at"],
            updated_at: response["data"]["updated_at"]
          }

          SmartPrompt.logger.info "Video status: #{status_data[:status]}, Progress: #{status_data[:progress]}"
          return status_data
        else
          SmartPrompt.logger.error "No status data in response"
          raise LLMAPIError, "No status data in response"
        end

      rescue => e
        SmartPrompt.logger.error "Error checking video status: #{e.message}"
        raise Error, "Error checking video status: #{e.message}"
      end
    end

    # Download video to file
    def download_video(video_url, output_path)
      SmartPrompt.logger.info "VideoGenerationAdapter: Downloading video"

      begin
        uri = URI.parse(video_url)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = (uri.scheme == 'https')

        request = Net::HTTP::Get.new(uri.request_uri)
        response = http.request(request)

        if response.is_a?(Net::HTTPSuccess)
          # Create directory if it doesn't exist
          FileUtils.mkdir_p(File.dirname(output_path))

          File.binwrite(output_path, response.body)
          SmartPrompt.logger.info "Video downloaded successfully to: #{output_path}"
          return output_path
        else
          SmartPrompt.logger.error "Failed to download video: #{response.code}"
          raise Error, "Failed to download video: #{response.code}"
        end

      rescue => e
        SmartPrompt.logger.error "Error downloading video: #{e.message}"
        raise Error, "Error downloading video: #{e.message}"
      end
    end

    # Wait for video generation to complete
    def wait_for_video_completion(job_id, check_interval: 10, timeout: 600)
      SmartPrompt.logger.info "VideoGenerationAdapter: Waiting for video generation to complete"

      start_time = Time.now

      loop do
        status = check_video_status(job_id)

        case status[:status]
        when "completed"
          SmartPrompt.logger.info "Video generation completed successfully"
          return status
        when "failed"
          SmartPrompt.logger.error "Video generation failed"
          raise LLMAPIError, "Video generation failed"
        when "cancelled"
          SmartPrompt.logger.error "Video generation was cancelled"
          raise LLMAPIError, "Video generation was cancelled"
        else
          # Still processing
          elapsed_time = Time.now - start_time
          if elapsed_time > timeout
            SmartPrompt.logger.error "Video generation timeout after #{timeout} seconds"
            raise LLMAPIError, "Video generation timeout"
          end

          SmartPrompt.logger.info "Video generation in progress: #{status[:progress]}%"
          sleep(check_interval)
        end
      end
    end

    private

    # Custom implementation for video generation API call
    def submit_video_generation_request(parameters)
      # Since OpenAI gem doesn't support video endpoints, we implement custom HTTP call
      uri = URI.parse("#{@config['url']}/videos/generations")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 600

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@config['api_key']}"

      request.body = parameters.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "Video generation API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for image-to-video API call
    def submit_image_to_video_request(parameters)
      uri = URI.parse("#{@config['url']}/videos/generations")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')
      http.read_timeout = 600

      request = Net::HTTP::Post.new(uri.request_uri)
      request['Content-Type'] = 'application/json'
      request['Authorization'] = "Bearer #{@config['api_key']}"

      request.body = parameters.to_json

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "Image-to-video API error: #{response.code} - #{response.body}"
      end
    end

    # Custom implementation for checking video generation status
    def check_video_generation_status(job_id)
      uri = URI.parse("#{@config['url']}/videos/#{job_id}")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == 'https')

      request = Net::HTTP::Get.new(uri.request_uri)
      request['Authorization'] = "Bearer #{@config['api_key']}"

      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        raise LLMAPIError, "Status check API error: #{response.code} - #{response.body}"
      end
    end

    # Override send_request to provide a meaningful error for chat operations
    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.error "VideoGenerationAdapter does not support chat operations. Use generate_video, create_video_from_image, or check_video_status methods instead."
      raise NotImplementedError, "VideoGenerationAdapter does not support chat operations"
    end

    # Override embeddings method
    def embeddings(text, model)
      SmartPrompt.logger.error "VideoGenerationAdapter does not support embeddings operations."
      raise NotImplementedError, "VideoGenerationAdapter does not support embeddings operations"
    end
  end
end