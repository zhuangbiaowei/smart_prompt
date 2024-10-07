require 'net/http'
require 'json'
require 'uri'
require 'openai'
require 'ollama-ai'

module SmartPrompt
  class LLMAdapter
    def initialize(config)
      SmartPrompt.logger.info "Start create the SmartPrompt LLMAdapter."
      @config = config
    end

    def send_request(messages)
      SmartPrompt.logger.error "LLMAdapter: Subclasses must implement send_request"
      raise NotImplementedError, "Subclasses must implement send_request"
    end
  end

  class OpenAIAdapter < LLMAdapter
    def initialize(config)
      super
      api_key = @config['api_key']
      if api_key.is_a?(String) && api_key.start_with?('ENV[') && api_key.end_with?(']')
        api_key = eval(api_key)
      end      
      @client = OpenAI::Client.new(
        access_token: api_key,
        uri_base: @config['url'],
        request_timeout: 240
      )
    end

    def send_request(messages, model=nil)
      SmartPrompt.logger.info "OpenAIAdapter: Sending request to OpenAI"
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      SmartPrompt.logger.info "OpenAIAdapter: Using model #{model_name}"
      response = @client.chat(
        parameters: {
          model: model_name,
          messages: messages,
          temperature: @config['temperature'] || 0.7
        }
      )
      SmartPrompt.logger.info "OpenAIAdapter: Received response from OpenAI"
      response.dig("choices", 0, "message", "content")
    end
  end

  class LlamacppAdapter < LLMAdapter
    def initialize(config)
      super
      @client = OpenAI::Client.new(
        uri_base: @config['url']
      )
    end
    def send_request(messages, model=nil)
      SmartPrompt.logger.info "LlamacppAdapter: Sending request to Llamacpp"
      response = @client.chat(
        parameters: {
          messages: messages,
          temperature: @config['temperature'] || 0.7
        }
      )
      SmartPrompt.logger.info "LlamacppAdapter: Received response from Llamacpp"
      response.dig("choices", 0, "message", "content")
    end
  end

  class OllamaAdapter < LLMAdapter
    def initialize(config)
      super
      @client = Ollama.new(credentials: { address: @config['url'] })
    end

    def send_request(messages, model=nil)
      SmartPrompt.logger.info "OllamaAdapter: Sending request to Ollama"
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      SmartPrompt.logger.info "OllamaAdapter: Using model #{model_name}"
      response = @client.generate(
        {
          model: model_name,
          prompt: messages.to_s,
          stream: false
        }
      )
      SmartPrompt.logger.info "OllamaAdapter: Received response from Ollama"
      return response[0]["response"]
    end
  end

  class MockAdapter < LLMAdapter
    def send_request(messages)
      puts "Mock adapter received #{messages.length} messages"
      "This is a mock response from the LLM adapter."
    end
  end
end