module SmartPrompt
  module ZhipuAI
    # Text chat + vision (OpenAI-compatible /chat/completions, SSE streaming,
    # reasoning_content passthrough). CodeGeeX/coding models use a separate base.
    module Text
      CHAT_OPTIONAL_KEYS = %w[
        top_p max_tokens do_sample stop presence_penalty frequency_penalty thinking
      ].freeze

      # Chat / multimodal. Non-streaming returns a full OpenAI-format hash (so
      # last_response carries usage + reasoning_content); streaming calls +proc+
      # with each OpenAI-shaped chunk.
      def send_request(messages, model = nil, temperature = nil, tools = nil, proc = nil)
        model_name = model || @config["model"]
        body = build_chat_body(messages, model_name, temperature, tools)
        SmartPrompt.logger.info "ZhipuAIAdapter: chat request model=#{model_name} stream=#{!proc.nil?}"

        url = chat_url_for(model_name)
        if proc
          body["stream"] = true
          stream_chat(url, body) { |data| proc.call(build_stream_chunk(data), 0) }
          SmartPrompt.logger.info "ZhipuAIAdapter: streaming request finished"
          nil
        else
          raw = http_post_json(url, body)
          response = build_completion_response(raw)
          @last_response = response
          SmartPrompt.logger.info "ZhipuAIAdapter: received chat response"
          response
        end
      rescue LLMAPIError, Error
        raise
      rescue => e
        SmartPrompt.logger.error "Zhipu chat error: #{e.message}"
        raise LLMAPIError, "Failed to call Zhipu chat: #{e.message}"
      end

      private

      def chat_url_for(model_name)
        # CodeGeeX-4 and coding models are served from the coding base.
        (model_name.to_s.include?("codegeex") || @config["coding"]) ? "#{@coding_base}/chat/completions" : "#{@base_url}/chat/completions"
      end

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
