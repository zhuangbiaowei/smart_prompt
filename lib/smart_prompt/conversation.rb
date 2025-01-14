require 'yaml'
require 'retriable'
require "numo/narray"

module SmartPrompt
  class Conversation
    include APIHandler
    attr_reader :messages, :last_response, :config_file

    def initialize(engine)
      SmartPrompt.logger.info "Create Conversation"
      @messages = []
      @engine = engine
      @adapters = engine.adapters
      @llms = engine.llms
      @templates = engine.templates
      @current_adapter = engine.current_adapter
      @last_response = nil
    end

    def use(llm_name)
      raise "Adapter #{adapter_name} not configured" unless @llms.key?(llm_name)
      @current_llm = @llms[llm_name]
      self
    end

    def model(model_name)
      @model_name = model_name
    end

    def temperature(temperature)
      @temperature = temperature
    end

    def prompt(template_name, params = {})
      if template_name.class == Symbol
        template_name = template_name.to_s
        SmartPrompt.logger.info "Use template #{template_name}"
        raise "Template #{template_name} not found" unless @templates.key?(template_name)
        content = @templates[template_name].render(params)
        @messages << { role: 'user', content: content }
        self
      else
        @messages << { role: 'user', content: template_name }
        self
      end
    end

    def sys_msg(message)
      @sys_msg = message
      @messages << { role: 'system', content: message }
      self
    end

    def send_msg
      raise "No LLM selected" if @current_llm.nil?
      @last_response = @current_llm.send_request(@messages, @model_name, @temperature)
      @messages=[]
      @messages << { role: 'system', content: @sys_msg }
      @last_response
    end

    def safe_send_msg
      Retriable.retriable(RETRY_OPTIONS) do
        raise ConfigurationError, "No LLM selected" if @current_llm.nil?
        @last_response = @current_llm.send_request(@messages, @model_name)
        @messages=[]
        @messages << { role: 'system', content: @sys_msg }
        @last_response
      end
    rescue => e
      return "Failed to call LLM after #{MAX_RETRIES} attempts: #{e.message}"
    end

    def normalize(x, length)
      if x.length > length
        x = Numo::NArray.cast(x[0..length-1])      
        norm = Math.sqrt((x * x).sum)
        return (x / norm).to_a
      else
        return x.concat([0] * (x.length - length))
      end
    end

    def embeddings(length)
      Retriable.retriable(RETRY_OPTIONS) do
        raise ConfigurationError, "No LLM selected" if @current_llm.nil?
        text = ""
        @messages.each do |msg|
          if msg[:role]=="user"
            text = msg[:content]
          end
        end
        @last_response = @current_llm.embeddings(text, @model_name)
        @messages=[]
        @messages << { role: 'system', content: @sys_msg }
        normalize(@last_response, length)
      end
    end
  end
end