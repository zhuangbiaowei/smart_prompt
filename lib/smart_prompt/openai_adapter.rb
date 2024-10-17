require 'openai'

module SmartPrompt
  class OpenAIAdapter < LLMAdapter
    def initialize(config)
      super
      api_key = @config['api_key']
      if api_key.is_a?(String) && api_key.start_with?('ENV[') && api_key.end_with?(']')
        api_key = eval(api_key)
      end
      begin
        @client = OpenAI::Client.new(
          access_token: api_key,
          uri_base: @config['url'],
          request_timeout: 240
        )        
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize OpenAI client: #{e.message}"
        raise LLMAPIError, "Invalid OpenAI configuration: #{e.message}"
      rescue OpenAI::AuthenticationError => e
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

    def send_request(messages, model=nil)
      SmartPrompt.logger.info "OpenAIAdapter: Sending request to OpenAI"
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      SmartPrompt.logger.info "OpenAIAdapter: Using model #{model_name}"
      begin
        response = @client.chat(
          parameters: {
            model: model_name,
            messages: messages,
            temperature: @config['temperature'] || 0.7
          }
        )
      rescue OpenAI::APIError => e
        SmartPrompt.logger.error "OpenAI API error: #{e.message}"
        raise LLMAPIError, "OpenAI API error: #{e.message}"
      rescue OpenAI::APIConnectionError => e
        SmartPrompt.logger.error "Connection error: Unable to reach OpenAI API"
        raise LLMAPIError, "Connection error: Unable to reach OpenAI API"
      rescue OpenAI::APITimeoutError => e
        SmartPrompt.logger.error "Request to OpenAI API timed out"
        raise LLMAPIError, "Request to OpenAI API timed out"
      rescue OpenAI::InvalidRequestError => e
        SmartPrompt.logger.error "Invalid request to OpenAI API: #{e.message}"
        raise LLMAPIError, "Invalid request to OpenAI API: #{e.message}"
      rescue OpenAI::AuthenticationError => e
        SmartPrompt.logger.error "Authentication error with OpenAI API: #{e.message}"
        raise LLMAPIError, "Authentication error with OpenAI API: #{e.message}"
      rescue OpenAI::RateLimitError => e
        SmartPrompt.logger.error "Rate limit exceeded for OpenAI API"
        raise LLMAPIError, "Rate limit exceeded for OpenAI API"
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
      response.dig("choices", 0, "message", "content")
    end
  end
end