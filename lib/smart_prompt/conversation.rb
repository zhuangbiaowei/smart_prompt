require "yaml"
require "retriable"
require "numo/narray"

module SmartPrompt
  class Conversation
    include APIHandler
    MODEL_REQUEST_OPTION_KEYS = %w[
      max_tokens
      max_completion_tokens
      top_p
      top_k
      response_format
      tool_choice
      parallel_tool_calls
      seed
      stop
    ].freeze

    attr_reader :messages, :last_response, :config_file
    attr_reader :last_call_id

    def initialize(engine, tools = nil)
      SmartPrompt.logger.info "Create Conversation"
      @messages = []
      @engine = engine
      @adapters = engine.adapters
      @llms = engine.llms
      @models = engine.models
      @current_llm_name = nil
      @templates = engine.templates
      @temperature = 0.7
      @current_adapter = engine.current_adapter
      @last_response = nil
      @tools = tools
      @request_options = {}
      @pending_content_parts = []
      @thinking_enabled = nil
    end

    def use(llm_name)
      llm_name = llm_name.to_s
      raise ConfigurationError, "LLM #{llm_name} not configured" unless @llms.key?(llm_name)
      @current_llm = @llms[llm_name]
      @current_llm_name = llm_name
      self
    end

    def use_model(model_name)
      model_name = model_name.to_s
      model_config = @models[model_name] || @models[model_name.to_sym]
      raise ConfigurationError, "Model #{model_name} not configured" unless model_config

      llm_name = model_config["use"] || model_config[:use]
      configured_model_name = model_config["model"] || model_config[:model]
      raise ConfigurationError, "Model #{model_name} must define use" if llm_name.nil? || llm_name.empty?
      raise ConfigurationError, "Model #{model_name} must define model" if configured_model_name.nil? || configured_model_name.empty?

      use(llm_name)
      model(configured_model_name)
      merge_model_request_options(model_config)
      self
    end

    def model(model_name)
      @model_name = model_name
    end

    def temperature(temperature)
      @temperature = temperature
    end

    def request_options(options = {})
      @request_options.merge!(options || {})
      self
    end

    def thinking(enabled = true)
      @thinking_enabled = enabled
      if @sys_msg
        @sys_msg = thinking_system_message(@sys_msg)
        refresh_system_message(@sys_msg)
      end
      self
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
        add_user_content(content, with_history)
        self
      else
        add_user_content(template_name, with_history)
        self
      end
    end

    def sys_msg(message, params)
      @sys_msg = thinking_system_message(message)
      add_message({ role: "system", content: @sys_msg }, params[:with_history])
      self
    end

    def multimodal_prompt(parts, with_history: false)
      add_message({ role: "user", content: normalize_content_parts(parts) }, with_history)
      self
    end

    def image(source, token_budget: nil, **metadata)
      @pending_content_parts << media_part("image", source, token_budget: token_budget, **metadata)
      self
    end

    def audio(source, **metadata)
      @pending_content_parts << media_part("audio", source, **metadata)
      self
    end

    def video(source, fps: nil, max_seconds: nil, **metadata)
      @pending_content_parts << media_part("video", source, fps: fps, max_seconds: max_seconds, **metadata)
      self
    end

    def send_msg_once
      raise "No LLM selected" if @current_llm.nil?
      @last_response = send_llm_request(@messages, nil)
      @messages = []
      @messages << { role: "system", content: @sys_msg }
      @last_response
    end

    def send_msg(params = {})
      Retriable.retriable(RETRY_OPTIONS) do
        raise ConfigurationError, "No LLM selected" if @current_llm.nil?
        if params[:with_history]
          @last_response = send_llm_request(history_messages, nil)
        else
          @last_response = send_llm_request(@messages, nil)
        end
        if @last_response == ""
          @last_response = @current_llm.last_response
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
        if params[:with_history]
          send_llm_request(history_messages, proc)
        else
          send_llm_request(@messages, proc)
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

    private

    def send_llm_request(messages, proc)
      parameters = @current_llm.method(:send_request).parameters
      if parameters.length >= 6
        @current_llm.send_request(messages, @model_name, @temperature, @tools, proc, @request_options)
      else
        @current_llm.send_request(messages, @model_name, @temperature, @tools, proc)
      end
    end

    def merge_model_request_options(model_config)
      explicit_options = model_config["request_options"] || model_config[:request_options] || {}
      @request_options.merge!(explicit_options)
      MODEL_REQUEST_OPTION_KEYS.each do |key|
        value = model_config[key] || model_config[key.to_sym]
        @request_options[key.to_sym] = value unless value.nil?
      end
    end

    def add_user_content(content, with_history)
      if @pending_content_parts.empty?
        add_message({ role: "user", content: content }, with_history)
      else
        add_message({ role: "user", content: multimodal_content(content) }, with_history)
        @pending_content_parts = []
      end
    end

    def multimodal_content(text)
      parts = @pending_content_parts
      images_and_videos = parts.select { |part| ["image", "video"].include?(part[:type] || part["type"]) }
      audio_parts = parts.select { |part| (part[:type] || part["type"]) == "audio" }
      other_parts = parts - images_and_videos - audio_parts
      normalize_content_parts(images_and_videos + other_parts + [{ type: "text", text: text.to_s }] + audio_parts)
    end

    def normalize_content_parts(parts)
      parts.map do |part|
        normalized = part.transform_keys(&:to_s)
        normalized["text"] = normalized.delete("content") if normalized["type"] == "text" && normalized.key?("content")
        normalized
      end
    end

    def media_part(type, source, **metadata)
      part = { type: type }
      case type
      when "image"
        part[:url] = source
      when "audio"
        part[:audio] = source
      when "video"
        part[:video] = source
      end
      metadata.each do |key, value|
        part[key] = value unless value.nil?
      end
      part
    end

    def thinking_system_message(message)
      message = message.to_s.sub(/\A<\|think\|>\n?/, "")
      return message if @thinking_enabled == false
      return message unless @thinking_enabled == true

      "<|think|>\n#{message}"
    end

    def refresh_system_message(message)
      system_message = @messages.find { |item| (item[:role] || item["role"]) == "system" }
      system_message[:content] = message if system_message
    end
  end
end
