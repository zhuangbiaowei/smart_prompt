require 'ollama-ai'

module SmartPrompt
  class OllamaAdapter < LLMAdapter
    def initialize(config)
      super
      begin
        @client = Ollama.new(credentials: { address: @config['url'] })
      rescue Ollama::Errors => e
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
      rescue Ollama::Errors => e
        SmartPrompt.logger.error "Ollama API error: #{e.message}"
        raise LLMAPIError, "Ollama API error: #{e.message}"      
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
      return response.dig(0,"response")
    end

    def embeddings(text, model)
      SmartPrompt.logger.info "OllamaAdapter: get embeddings from Ollama"
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      SmartPrompt.logger.info "OllamaAdapter: Using model #{model_name}"
      begin
        response = @client.embeddings(
            {
              model: model_name,
              prompt: text.to_s
            }
        )
      rescue => e
        SmartPrompt.logger.error "Unexpected error during Ollama request: #{e.message}"
        raise Error, "Unexpected error during Ollama request: #{e.message}"
      ensure
        SmartPrompt.logger.info "Successful send a message"
      end
      return response.dig(0,"embedding")
    end
  end
end