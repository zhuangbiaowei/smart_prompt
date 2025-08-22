require "yaml"
require "retriable"
require "numo/narray"

module SmartPrompt
  class Conversation
    include APIHandler
    attr_reader :messages, :last_response, :config_file
    attr_reader :last_call_id

    def initialize(engine, tools = nil)
      SmartPrompt.logger.info "Create Conversation"
      @messages = []
      @engine = engine
      @adapters = engine.adapters
      @llms = engine.llms
      @current_llm_name = nil
      @templates = engine.templates
      @temperature = 0.7
      @current_adapter = engine.current_adapter
      @last_response = nil
      @tools = tools
    end

    def use(llm_name)
      raise "Adapter #{adapter_name} not configured" unless @llms.key?(llm_name)
      @current_llm = @llms[llm_name]
      @current_llm_name = llm_name
      self
    end

    def model(model_name)
      @model_name = model_name
      if @engine.config["better_prompt_db"]
        BetterPrompt.add_model(@current_llm_name, @model_name)
      end
    end

    def temperature(temperature)
      @temperature = temperature
    end

    def history_messages
      @engine.history_messages
    end

    def add_message(msg, with_history = false)
      if with_history
        history_messages << msg
      end
      @messages << msg
    end

    def prompt(template_name, params = {}, with_history: false)
      if template_name.class == Symbol
        template_name = template_name.to_s
        SmartPrompt.logger.info "Use template #{template_name}"
        raise "Template #{template_name} not found" unless @templates.key?(template_name)
        content = @templates[template_name].render(params)
        add_message({ role: "user", content: content }, with_history)
        if @engine.config["better_prompt_db"]
          BetterPrompt.add_prompt(template_name, "user", content)
        end
        self
      else
        add_message({ role: "user", content: template_name }, with_history)
        if @engine.config["better_prompt_db"]
          BetterPrompt.add_prompt("NULL", "user", template_name)
        end
        self
      end
    end

    def sys_msg(message, params)
      @sys_msg = message
      add_message({ role: "system", content: message }, params[:with_history])
      if @engine.config["better_prompt_db"]
        BetterPrompt.add_prompt("NULL", "system", message)
      end
      self
    end

    def send_msg_once
      raise "No LLM selected" if @current_llm.nil?
      @last_response = @current_llm.send_request(@messages, @model_name, @temperature)
      @messages = []
      @messages << { role: "system", content: @sys_msg }
      @last_response
    end

    def send_msg(params = {})
      Retriable.retriable(RETRY_OPTIONS) do
        raise ConfigurationError, "No LLM selected" if @current_llm.nil?
        if @engine.config["better_prompt_db"]
          if params[:with_history]
            @last_call_id = BetterPrompt.add_model_call(@current_llm_name, @model_name, history_messages, false, @temperature, 0, 0.0, 0, @tools)
          else
            @last_call_id = BetterPrompt.add_model_call(@current_llm_name, @model_name, @messages, false, @temperature, 0, 0.0, 0, @tools)
          end
        end
        if params[:with_history]
          @last_response = @current_llm.send_request(history_messages, @model_name, @temperature, @tools, nil)
        else
          @last_response = @current_llm.send_request(@messages, @model_name, @temperature, @tools, nil)
        end
        if @last_response == ""
          @last_response = @current_llm.last_response
        end
        if @engine.config["better_prompt_db"]
          BetterPrompt.add_response(@last_call_id, @last_response, false)
        end
        @messages = []
        @messages << { role: "system", content: @sys_msg }
        @last_response
      end
    rescue => e
      return "Failed to call LLM after #{MAX_RETRIES} attempts: #{e.message}"
    end

    def send_msg_by_stream(params = {}, &proc)
      Retriable.retriable(RETRY_OPTIONS) do
        raise ConfigurationError, "No LLM selected" if @current_llm.nil?
        if @engine.config["better_prompt_db"]
          if params[:with_history]
            @last_call_id = BetterPrompt.add_model_call(@current_llm_name, @model_name, history_messages, true, @temperature, 0, 0.0, 0, @tools)
          else
            @last_call_id = BetterPrompt.add_model_call(@current_llm_name, @model_name, @messages, true, @temperature, 0, 0.0, 0, @tools)
          end
        end
        if params[:with_history]
          @current_llm.send_request(history_messages, @model_name, @temperature, @tools, proc)
        else
          @current_llm.send_request(@messages, @model_name, @temperature, @tools, proc)
        end
        if @engine.config["better_prompt_db"]
          BetterPrompt.add_response(@last_call_id, @engine.stream_response, true)
        end
        @messages = []
        @messages << { role: "system", content: @sys_msg }
      end
    rescue => e
      return "Failed to call LLM after #{MAX_RETRIES} attempts: #{e.message}"
    end

    def normalize(x, length)
      if x.length > length
        x = Numo::NArray.cast(x[0..length - 1])
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
          if msg[:role] == "user"
            text = msg[:content]
          end
        end
        @last_response = @current_llm.embeddings(text, @model_name)
        @messages = []
        @messages << { role: "system", content: @sys_msg }
        normalize(@last_response, length)
      end
    end
  end
end
