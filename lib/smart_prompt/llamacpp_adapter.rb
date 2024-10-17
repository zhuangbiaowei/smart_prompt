require 'openai'

module SmartPrompt
  class LlamacppAdapter < LLMAdapter
    def initialize(config)
      super
      begin
        @client = OpenAI::Client.new(
            uri_base: @config['url']
          )
      rescue OpenAI::ConfigurationError => e
        SmartPrompt.logger.error "Failed to initialize Llamacpp client: #{e.message}"
        raise LLMAPIError, "Invalid Llamacpp configuration: #{e.message}"
      rescue OpenAI::AuthenticationError => e
        SmartPrompt.logger.error "Failed to initialize Llamacpp client: #{e.message}"
        raise LLMAPIError, "Llamacpp authentication failed: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize Llamacpp client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to Llamacpp API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize Llamacpp client: #{e.message}"
        raise Error, "Unexpected error initializing Llamacpp client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful creation an Llamacpp client."        
      end
    end

    def send_request(messages, model=nil)
      SmartPrompt.logger.info "LlamacppAdapter: Sending request to Llamacpp"
      begin
      response = @client.chat(
        parameters: {
          messages: messages,
          temperature: @config['temperature'] || 0.7
        }
      )
      rescue OpenAI::APIError => e
        SmartPrompt.logger.error "Llamacpp API error: #{e.message}"
        raise LLMAPIError, "Llamacpp API error: #{e.message}"
      rescue OpenAI::APIConnectionError => e
        SmartPrompt.logger.error "Connection error: Unable to reach Llamacpp API"
        raise LLMAPIError, "Connection error: Unable to reach Llamacpp API"
      rescue OpenAI::APITimeoutError => e
        SmartPrompt.logger.error "Request to Llamacpp API timed out"
        raise LLMAPIError, "Request to Llamacpp API timed out"
      rescue OpenAI::InvalidRequestError => e
        SmartPrompt.logger.error "Invalid request to Llamacpp API: #{e.message}"
        raise LLMAPIError, "Invalid request to Llamacpp API: #{e.message}"
      rescue OpenAI::AuthenticationError => e
        SmartPrompt.logger.error "Authentication error with Llamacpp API: #{e.message}"
        raise LLMAPIError, "Authentication error with Llamacpp API: #{e.message}"
      rescue OpenAI::RateLimitError => e
        SmartPrompt.logger.error "Rate limit exceeded for Llamacpp API"
        raise LLMAPIError, "Rate limit exceeded for Llamacpp API"
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse Llamacpp API response"
        raise LLMAPIError, "Failed to parse Llamacpp API response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during Llamacpp request: #{e.message}"
        raise Error, "Unexpected error during Llamacpp request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful send a message"
      end
      SmartPrompt.logger.info "LlamacppAdapter: Received response from Llamacpp"
      response.dig("choices", 0, "message", "content")
    end
  end
end  