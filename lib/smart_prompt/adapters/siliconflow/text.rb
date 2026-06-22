module SmartPrompt
  module SiliconFlow
    # Text chat + multimodal vision (OpenAI-compatible /chat/completions, SSE streaming,
    # reasoning_content passthrough).
    module Text
      CHAT_OPTIONAL_KEYS = %w[
        top_p top_k frequency_penalty presence_penalty
        max_tokens max_completion_tokens stop response_format
        enable_thinking thinking_budget min_p reasoning_effort seed
      ].freeze

      # Chat / multimodal. Non-streaming returns a full OpenAI-format hash (so
      # last_response carries usage + reasoning_content); streaming calls +proc+
      # with each OpenAI-shaped chunk and returns nil.
      def send_request(messages, model = nil, temperature = nil, tools = nil, proc = nil)
        model_name = model || @config["model"]
        body = build_chat_body(messages, model_name, temperature, tools)
        SmartPrompt.logger.info "SiliconFlowAdapter: chat request model=#{model_name} stream=#{!proc.nil?}"

        url = "#{@base_url}/chat/completions"
        if proc
          body["stream"] = true
          stream_chat(url, body) { |data| proc.call(build_stream_chunk(data), 0) }
          SmartPrompt.logger.info "SiliconFlowAdapter: streaming request finished"
          nil
        else
          raw = http_post_json(url, body)
          response = build_completion_response(raw)
          @last_response = response
          SmartPrompt.logger.info "SiliconFlowAdapter: received chat response"
          response
        end
      rescue LLMAPIError, Error
        raise
      rescue => e
        SmartPrompt.logger.error "SiliconFlow chat error: #{e.message}"
        raise LLMAPIError, "Failed to call SiliconFlow chat: #{e.message}"
      end

      private

      def build_chat_body(messages, model_name, temperature, tools)
        body = {
          "model"       => model_name,
          "messages"    => process_multimodal_messages(messages),
          "temperature" => @config["temperature"] || temperature || 0.7,
        }
        CHAT_OPTIONAL_KEYS.each { |k| body[k] = @config[k] if @config.key?(k) }
        body["tools"] = tools if tools && !tools.empty?
        body
      end
    end
  end
end
