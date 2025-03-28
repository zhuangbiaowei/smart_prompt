require 'net/http'
require 'json'
require 'uri'

module SmartPrompt
  class LLMAdapter
    attr_accessor :last_response
    def initialize(config)
      SmartPrompt.logger.info "Start create the SmartPrompt LLMAdapter."
      @config = config
    end

    def send_request(messages)
      SmartPrompt.logger.error "LLMAdapter: Subclasses must implement send_request"
      raise NotImplementedError, "Subclasses must implement send_request"
    end
  end

  class MockAdapter < LLMAdapter
    def send_request(messages)
      puts "Mock adapter received #{messages.length} messages"
      "This is a mock response from the LLM adapter."
    end
  end
end