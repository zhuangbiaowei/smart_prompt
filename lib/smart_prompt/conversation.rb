require 'yaml'

module SmartPrompt
  class Conversation
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

    def prompt(template_name, params = {})
      template_name = template_name.to_s
      SmartPrompt.logger.info "Use template #{template_name}"
      raise "Template #{template_name} not found" unless @templates.key?(template_name)
      content = @templates[template_name].render(params)
      @messages << { role: 'user', content: content }
      self
    end

    def sys_msg(message)
      @sys_msg = message
      @messages << { role: 'system', content: message }
      self
    end

    def send_msg
      raise "No LLM selected" if @current_llm.nil?
      @last_response = @current_llm.send_request(@messages, @model_name)
      @messages=[]
      @messages << { role: 'system', content: @sys_msg }
      @last_response
    end
  end
end