require "openai"

module SmartPrompt
  class OpenAIAdapter < LLMAdapter
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
        SmartPrompt.logger.error "Failed to initialize OpenAI client: #{e.message}"
        raise LLMAPIError, "Invalid OpenAI configuration: #{e.message}"
      rescue OpenAI::Error => e
        SmartPrompt.logger.error "Failed to initialize OpenAI client: #{e.message}"
        raise LLMAPIError, "OpenAI authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize OpenAI client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to OpenAI API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize OpenAI client: #{e.message}"
        raise Error, "Unexpected error initializing OpenAI client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful creation an OpenAI client."
      end
    end

    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.info "OpenAIAdapter: Sending request to OpenAI"
      temperature = 0.7 if temperature == nil
      if model
        model_name = model
      else
        model_name = @config["model"]
      end
      SmartPrompt.logger.info "OpenAIAdapter: Using model #{model_name}"
      begin
        parameters = {
          model: model_name,
          messages: messages,
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
        SmartPrompt.logger.error "OpenAI API error: #{e.message}"
        raise LLMAPIError, "OpenAI API error: #{e.message}"
      rescue OpenAI::MiddlewareErrors => e
        SmartPrompt.logger.error "OpenAI HTTP Error: #{e.message}"
        raise LLMAPIError, "OpenAI HTTP Error"
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse OpenAI API response"
        raise LLMAPIError, "Failed to parse OpenAI API response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during OpenAI request: #{e.message}"
        raise Error, "Unexpected error during OpenAI request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful send a message"
      end
      SmartPrompt.logger.info "OpenAIAdapter: Received response from OpenAI"
      if proc == nil
        @last_response = response
        return response.dig("choices", 0, "message", "content")
      end
    end

    def embeddings(text, model)
      SmartPrompt.logger.info "OpenAIAdapter: get embeddings from Ollama"
      if model
        model_name = model
      else
        model_name = @config["model"]
      end
      SmartPrompt.logger.info "OpenAIAdapter: Using model #{model_name}"
      begin
        response = @client.embeddings(
          parameters: {
            model: model_name,
            input: text.to_s,
          },
        )
      rescue => e
        SmartPrompt.logger.error "Unexpected error during Ollama request: #{e.message}"
        raise Error, "Unexpected error during Ollama request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful send a message"
      end
      return response.dig("data", 0, "embedding")
    end
  end
end
