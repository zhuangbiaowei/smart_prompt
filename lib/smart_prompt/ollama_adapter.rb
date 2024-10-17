require 'ollama-ai'

module SmartPrompt
  class OllamaAdapter < LLMAdapter
    def initialize(config)
      super
      begin
        @client = Ollama.new(credentials: { address: @config['url'] })
      rescue Ollama::Error => e
        SmartPrompt.logger.error "Failed to initialize Ollama client: #{e.message}"
        raise LLMAPIError, "Invalid Ollama configuration: #{e.message}"
      rescue SocketError => e
        SmartPrompt.logger.error "Failed to initialize Ollama client: #{e.message}"
        raise LLMAPIError, "Network error: Unable to connect to Ollama API"
      rescue => e
        SmartPrompt.logger.error "Failed to initialize Ollama client: #{e.message}"
        raise Error, "Unexpected error initializing Ollama client: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful creation an Ollama client."
      end
    end

    def send_request(messages, model=nil)
      SmartPrompt.logger.info "OllamaAdapter: Sending request to Ollama"
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      SmartPrompt.logger.info "OllamaAdapter: Using model #{model_name}"
      begin
        response = @client.generate(
            {
            model: model_name,
            prompt: messages.to_s,
            stream: false
            }
        )
      rescue Ollama::Error => e
        SmartPrompt.logger.error "Ollama API error: #{e.message}"
        raise LLMAPIError, "Ollama API error: #{e.message}"
      rescue Ollama::ConnectionError => e
        SmartPrompt.logger.error "Connection error: Unable to reach Ollama API"
        raise LLMAPIError, "Connection error: Unable to reach Ollama API"
      rescue Ollama::TimeoutError => e
        SmartPrompt.logger.error "Request to Ollama API timed out"
        raise LLMAPIError, "Request to Ollama API timed out"
      rescue Ollama::InvalidRequestError => e
        SmartPrompt.logger.error "Invalid request to Ollama API: #{e.message}"
        raise LLMAPIError, "Invalid request to Ollama API: #{e.message}"
      rescue JSON::ParserError => e
        SmartPrompt.logger.error "Failed to parse Ollama API response"
        raise LLMAPIError, "Failed to parse Ollama API response"
      rescue => e
        SmartPrompt.logger.error "Unexpected error during Ollama request: #{e.message}"
        raise Error, "Unexpected error during Ollama request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful send a message"
      end
      SmartPrompt.logger.info "OllamaAdapter: Received response from Ollama"
      return response[0]["response"]
    end
  end
end