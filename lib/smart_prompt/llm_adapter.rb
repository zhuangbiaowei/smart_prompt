require 'net/http'
require 'json'
require 'uri'
require 'openai'
require 'ollama-ai'

module SmartPrompt
  class LLMAdapter
    def initialize(config)
      @config = config
    end

    def send_request(messages)
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
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      response = @client.chat(
        parameters: {
          model: model_name,
          messages: messages,
          temperature: @config['temperature'] || 0.7
        }
      )
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
      response = @client.chat(
        parameters: {
          messages: messages,
          temperature: @config['temperature'] || 0.7
        }
      )
      response.dig("choices", 0, "message", "content")
    end
  end

  class OllamaAdapter < LLMAdapter
    def initialize(config)
      super
      @client = Ollama.new(credentials: { address: @config['url'] })
    end

    def send_request(messages, model=nil)
      if model
        model_name = model
      else
        model_name = @config['model']        
      end
      response = @client.generate(
        {
          model: model_name,
          prompt: messages.to_s,
          stream: false
        }
      )
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