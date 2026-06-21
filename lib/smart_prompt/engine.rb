module SmartPrompt
  class Engine
    attr_reader :config_file, :config, :adapters, :current_adapter, :llms, :models, :templates
    attr_reader :stream_response, :history_manager

    def initialize(config_file)
      @config_file = config_file
      @adapters = {}
      @llms = {}
      @models = {}
      @templates = {}
      @current_workers = {}
      @history_messages = []
      @history_manager = nil
      load_config(config_file)
      SmartPrompt.logger.info "Started create the SmartPrompt engine."
      @stream_proc = Proc.new do |chunk, _bytesize|
        if @stream_response.empty?
          @stream_response["id"] = chunk["id"]
          @stream_response["object"] = chunk["object"]
          @stream_response["created"] = chunk["created"]
          @stream_response["model"] = chunk["model"]
          @stream_response["choices"] = [{
            "index" => 0,
            "message" => {
              "role" => "assistant",
              "content" => "",
              "reasoning_content" => "",
              "tool_calls" => [],
            },
          }]
          @stream_response["usage"] = chunk["usage"]
          @stream_response["system_fingerprint"] = chunk["system_fingerprint"]
        end
        if chunk.dig("choices", 0, "delta", "reasoning_content")
          @stream_response["choices"][0]["message"]["reasoning_content"] += chunk.dig("choices", 0, "delta", "reasoning_content")
        end
        if chunk.dig("choices", 0, "delta", "content")
          @stream_response["choices"][0]["message"]["content"] += chunk.dig("choices", 0, "delta", "content")
        end
        if chunk_tool_calls = chunk.dig("choices", 0, "delta", "tool_calls")
          chunk_tool_calls.each do |tool_call|
            if @stream_response["choices"][0]["message"]["tool_calls"].size > tool_call["index"]
              @stream_response["choices"][0]["message"]["tool_calls"][tool_call["index"]]["function"]["arguments"] += tool_call["function"]["arguments"]
            else
              @stream_response["choices"][0]["message"]["tool_calls"] << tool_call
            end
          end
        end
        @origin_proc.call(chunk, _bytesize)
      end
    end

    def create_dir(filename)
      path = File::path(filename).to_s
      parent_dir = File::dirname(path)
      Dir.mkdir(parent_dir, 0755) unless File.directory?(parent_dir)
    end

    def load_config(config_file)
      begin
        @config_file = config_file
        @config = YAML.load_file(config_file)
        if @config["logger_file"]
          create_dir(@config["logger_file"])
          SmartPrompt.logger = Logger.new(@config["logger_file"])
        end
        SmartPrompt.logger.info "Loading configuration from file: #{config_file}"
        @models = @config["models"] || {}
        @config["adapters"].each do |adapter_name, adapter_class|
          adapter_class = SmartPrompt.const_get(adapter_class)
          @adapters[adapter_name] = adapter_class
        end
        @config["llms"].each do |llm_name, llm_config|
          adapter_class = @adapters[llm_config["adapter"]]
          @llms[llm_name] = adapter_class.new(llm_config)
        end
        @current_llm = @config["default_llm"] if @config["default_llm"]
        Dir.glob(File.join(@config["template_path"], "*.erb")).each do |file|
          template_name = file.gsub(@config["template_path"] + "/", "").gsub("\.erb", "")
          @templates[template_name] = PromptTemplate.new(file)
        end

        # Initialize HistoryManager if configured
        if @config["history"]
          history_config = symbolize_keys(@config["history"])
          @history_manager = HistoryManager.new(history_config)
          SmartPrompt.logger.info "HistoryManager initialized with configuration"
        end

        load_workers
      rescue Psych::SyntaxError => ex
        SmartPrompt.logger.error "YAML syntax error in config file: #{ex.message}"
        raise ConfigurationError, "Invalid YAML syntax in config file: #{ex.message}"
      rescue Errno::ENOENT => ex
        SmartPrompt.logger.error "Config file not found: #{ex.message}"
        raise ConfigurationError, "Config file not found: #{ex.message}"
      rescue StandardError => ex
        SmartPrompt.logger.error "Error loading configuration: #{ex.message}"
        raise ConfigurationError, "Error loading configuration: #{ex.message}"
      ensure
        SmartPrompt.logger.info "Configuration loaded successfully"
      end
    end

    def load_workers
      Dir.glob(File.join(@config["worker_path"], "*.rb")).each do |file|
        require(file)
      end
    end

    def check_worker(worker_name)
      if SmartPrompt::Worker.workers[worker_name]
        return true
      else
        SmartPrompt.logger.warn "Invalid worker: #{worker_name}"
        return false
      end
    end

    def call_worker(worker_name, params = {})
      SmartPrompt.logger.info "Calling worker: #{worker_name} with params: #{params}"
      worker = get_worker(worker_name)
      begin
        unless params[:with_history]
          if worker.conversation
            worker.conversation.messages.clear
          end
        end
        result = worker.execute(params)
        SmartPrompt.logger.info "Worker #{worker_name} executed successfully"
        if result.class == String
          recive_message = {
            "role": "assistant",
            "content": sanitize_history_content(result),
          }
        elsif result.class == Array
          recive_message = nil
        else
          recive_message = assistant_history_message(result)
        end
        worker.conversation.add_message(recive_message) if recive_message
        SmartPrompt.logger.info "Worker result is: #{result}"
        result
      rescue => e
        SmartPrompt.logger.error "Error executing worker #{worker_name}: #{e.message}"
        SmartPrompt.logger.debug e.backtrace.join("\n")
        raise
      end
    end

    def call_worker_by_stream(worker_name, params = {}, &proc)
      SmartPrompt.logger.info "Calling worker: #{worker_name} with params: #{params}"
      worker = get_worker(worker_name)
      begin
        @origin_proc = proc
        @stream_response = {}
        ret = worker.execute_by_stream(params, &@stream_proc)
        @stream_response = ret if @stream_response.empty?
        SmartPrompt.logger.info "Worker #{worker_name} executed(stream) successfully"
        SmartPrompt.logger.info "Worker #{worker_name} stream response is: #{@stream_response}"
      rescue => e
        SmartPrompt.logger.error "Error executing worker #{worker_name}: #{e.message}"
        SmartPrompt.logger.debug e.backtrace.join("\n")
        raise
      end
    end

    def get_worker(worker_name)
      SmartPrompt.logger.info "Creating worker instance for: #{worker_name}"
      unless worker = @current_workers[worker_name]
        worker = Worker.new(worker_name, self)
        @current_workers[worker_name] = worker
      end
      return worker
    end

    def history_messages
      if @history_manager
        SmartPrompt.logger.warn "[DEPRECATED] Engine#history_messages is deprecated. Use history_manager.get_context(session_id) instead."
      end
      @history_messages
    end

    def clear_history_messages
      if @history_manager
        SmartPrompt.logger.warn "[DEPRECATED] Engine#clear_history_messages is deprecated. Use history_manager.clear_session(session_id) instead."
      end
      @history_messages = []
    end

    private

    def assistant_history_message(result)
      message = result.dig("choices", 0, "message") || {}
      history_message = {
        "role": message["role"] || "assistant",
        "content": sanitize_history_content(message["content"].to_s),
      }
      tool_calls = message["tool_calls"]
      history_message["tool_calls"] = tool_calls if tool_calls && !tool_calls.empty?
      history_message
    end

    def sanitize_history_content(content)
      content.to_s.gsub(/<\|channel\>thought\n.*?<channel\|>/m, "")
    end

    # Recursively convert hash keys from strings to symbols
    def symbolize_keys(hash)
      return hash unless hash.is_a?(Hash)

      hash.each_with_object({}) do |(key, value), result|
        new_key = key.is_a?(String) ? key.to_sym : key
        new_value = value.is_a?(Hash) ? symbolize_keys(value) : value
        result[new_key] = new_value
      end
    end
  end
end
