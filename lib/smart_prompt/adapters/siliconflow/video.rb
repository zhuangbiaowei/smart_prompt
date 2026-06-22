module SmartPrompt
  module SiliconFlow
    # Text-to-video / image-to-video (Wan2.2, async submit -> poll -> download).
    module Video
      # Text-to-video image_size enum (SiliconFlow rejects anything else).
      VALID_VIDEO_SIZES = %w[1280x720 720x1280 960x960].freeze
      DEFAULT_VIDEO_SIZE = "1280x720".freeze

      # Submit a text-to-video (or image-to-video) job. Returns the requestId.
      # SiliconFlow's submit endpoint returns {"requestId": "..."} (camelCase).
      def generate_video(prompt, params = {})
        SmartPrompt.logger.info "SiliconFlowAdapter: submitting video job"
        model_name = params[:model] || @config["video_model"] || @config["model"]
        raise Error, "No model configured for video generation" if model_name.nil? || model_name.to_s.strip.empty?

        body = { "model" => model_name, "prompt" => prompt.to_s }
        body["image_size"]      = resolve_video_size(params[:image_size] || params[:size])
        body["negative_prompt"] = params[:negative_prompt] if params[:negative_prompt]
        body["seed"]            = params[:seed]            if params[:seed]
        body["image"]           = normalize_input_image(params[:image]) if params[:image]

        SmartPrompt.logger.info "SiliconFlow video params: #{body.except('prompt').inspect}"
        response =
          begin
            http_post_json(@video_submit_url, body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise Error, "Failed to submit SiliconFlow video job: #{e.message}"
          end

        request_id = response["requestId"] || response["request_id"]
        raise LLMAPIError, "No requestId in SiliconFlow video response: #{response.inspect}" unless request_id
        SmartPrompt.logger.info "SiliconFlowAdapter: video request #{request_id} submitted"
        { request_id: request_id, model: model_name, raw: response }
      end

      # Poll an async task. SiliconFlow's status endpoint is a POST (NOT GET) that
      # takes {requestId} in the body. Returns the raw status hash.
      def check_video_status(request_id)
        SmartPrompt.logger.info "SiliconFlowAdapter: polling video request #{request_id}"
        http_post_json(@video_status_url, { "requestId" => request_id })
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise LLMAPIError, "Failed to query SiliconFlow video status: #{e.message}"
      end

      # Block until the task finishes (or times out), then return the video URL.
      # SiliconFlow status values are exactly: Succeeded / InQueue / InProgress / Failed.
      def wait_for_video_completion(request_id, check_interval: 10, timeout: 600)
        start = Time.now
        loop do
          status = check_video_status(request_id)
          case video_status_of(status)
          when "Succeed"
            url = video_url_of(status)
            raise LLMAPIError, "Video succeeded but no url in: #{status.inspect}" unless url
            SmartPrompt.logger.info "SiliconFlowAdapter: video ready #{url}"
            return { request_id: request_id, status: "Succeeded", video_url: url, raw: status }
          when "Failed"
            raise LLMAPIError, "SiliconFlow video generation failed: #{status["reason"] || status.inspect}"
          else
            if Time.now - start > timeout
              raise LLMAPIError, "SiliconFlow video generation timeout after #{timeout}s"
            end
            SmartPrompt.logger.info "SiliconFlow video request #{request_id} #{video_status_of(status)}..."
            sleep(check_interval)
          end
        end
      end

      def download_video(video_url, output_path)
        uri = URI.parse(video_url)
        http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
        response = http.request(Net::HTTP::Get.new(uri.request_uri))
        raise Error, "Failed to download video: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
        FileUtils.mkdir_p(File.dirname(output_path))
        File.binwrite(output_path, response.body)
        SmartPrompt.logger.info "SiliconFlow video saved to #{output_path}"
        output_path
      rescue => e
        raise e.is_a?(SmartPrompt::Error) ? e : Error, "Error downloading SiliconFlow video: #{e.message}"
      end

      private

      # SiliconFlow video status is under the top-level `status` field.
      def video_status_of(status)
        status["status"] || "InQueue"
      end

      # The video url lives at results.videos[].url (results is an OBJECT, not array).
      def video_url_of(status)
        videos = status.dig("results", "videos")
        item = videos.is_a?(Array) ? videos[0] : videos
        item.is_a?(Hash) ? (item["url"] || item["video_url"]) : nil
      end

      # Resolve the video image_size: default 1280x720; warn on unknown values.
      def resolve_video_size(size)
        size = size.nil? || size.to_s.strip.empty? ? DEFAULT_VIDEO_SIZE : size.to_s
        unless VALID_VIDEO_SIZES.include?(size)
          SmartPrompt.logger.warn "SiliconFlow video image_size '#{size}' is not in the known-valid list " \
                                  "(#{VALID_VIDEO_SIZES.join(', ')}); the API may reject it."
        end
        size
      end
    end
  end
end
