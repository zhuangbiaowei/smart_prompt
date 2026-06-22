module SmartPrompt
  module ZhipuAI
    # Text-to-video / image-to-video (CogVideoX, async submit -> poll -> download).
    module Video
      # Submit a text-to-video (or image-to-video) job. Returns the task id.
      def generate_video(prompt, params = {})
        SmartPrompt.logger.info "ZhipuAIAdapter: submitting video job"
        model_name = params[:model] || @config["video_model"] || @config["model"]
        raise Error, "No model configured for video generation" if model_name.nil? || model_name.to_s.strip.empty?

        body = { "model" => model_name, "prompt" => prompt.to_s }
        %i[quality fps duration with_audio resolution request_id seed].each do |k|
          body[k.to_s] = params[k] unless params[k].nil?
        end
        body["image_url"] = normalize_image_url(params[:image_url]) if params[:image_url]

        SmartPrompt.logger.info "Zhipu video params: #{body.except('prompt').inspect}"
        response =
          begin
            http_post_json(@video_url, body)
          rescue LLMAPIError, Error
            raise
          rescue => e
            raise Error, "Failed to submit Zhipu video job: #{e.message}"
          end

        task_id = response["id"] || response["task_id"]
        raise LLMAPIError, "No task id in Zhipu video response: #{response.inspect}" unless task_id
        SmartPrompt.logger.info "ZhipuAIAdapter: video task #{task_id} submitted"
        { task_id: task_id, model: model_name, raw: response }
      end

      # Poll an async task. Returns the raw status hash (task_status etc.).
      def check_video_status(task_id)
        SmartPrompt.logger.info "ZhipuAIAdapter: polling video task #{task_id}"
        http_get_json("#{@query_url}/#{URI.encode_www_form_component(task_id)}")
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise LLMAPIError, "Failed to query Zhipu video task: #{e.message}"
      end

      # Block until the task finishes (or times out), then return the video URL.
      def wait_for_video_completion(task_id, check_interval: 10, timeout: 600)
        start = Time.now
        loop do
          status = check_video_status(task_id)
          case task_status_of(status)
          when "SUCCESS"
            url = video_url_of(status)
            raise LLMAPIError, "Video succeeded but no url in: #{status.inspect}" unless url
            SmartPrompt.logger.info "ZhipuAIAdapter: video ready #{url}"
            return { task_id: task_id, status: "SUCCESS", video_url: url, cover_image_url: cover_url_of(status), raw: status }
          when "FAIL", "FAILED"
            raise LLMAPIError, "Zhipu video generation failed: #{status.inspect}"
          else
            if Time.now - start > timeout
              raise LLMAPIError, "Zhipu video generation timeout after #{timeout}s"
            end
            SmartPrompt.logger.info "Zhipu video task #{task_id} still processing..."
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
        SmartPrompt.logger.info "Zhipu video saved to #{output_path}"
        output_path
      rescue => e
        raise e.is_a?(SmartPrompt::Error) ? e : Error, "Error downloading Zhipu video: #{e.message}"
      end

      private

      # Zhipu async task status is under task_status; accept a few aliases.
      def task_status_of(status)
        status["task_status"] || status["status"] || "PROCESSING"
      end

      # video_result is an Array: [{cover_image_url:, url:}]. Pull the first video url.
      def video_url_of(status)
        vr = status["video_result"]
        item = vr.is_a?(Array) ? vr[0] : vr
        return item["url"] || item["video_url"] if item.is_a?(Hash)
        status["video_url"] || status.dig("data", "video_url")
      end

      def cover_url_of(status)
        vr = status["video_result"]
        item = vr.is_a?(Array) ? vr[0] : vr
        item.is_a?(Hash) ? (item["cover_image_url"] || item["cover_url"]) : nil
      end
    end
  end
end
