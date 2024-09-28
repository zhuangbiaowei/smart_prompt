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

  class OpenaiAdapter < LLMAdapter
    def initialize(config)
      super
      @client = OpenAI::Client.new(
        access_token: @config['api_key'],
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