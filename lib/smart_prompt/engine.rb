module SmartPrompt
    class Engine
      attr_reader :config_file, :config, :adapters, :current_adapter, :llms, :templates
      def initialize(config_file)
        @config_file = config_file
        @adapters={}
        @llms={}
        @templates={}
        load_config(config_file)
        SmartPrompt.logger.info "Started create the SmartPrompt engine."
      end

      def load_config(config_file)
        begin
          @config_file = config_file
          @config = YAML.load_file(config_file)
          if @config['logger_file']
            SmartPrompt.logger = Logger.new(@config['logger_file'])
          end
          SmartPrompt.logger.info "Loading configuration from file: #{config_file}"
          @config['adapters'].each do |adapter_name, adapter_class|
            adapter_class = SmartPrompt.const_get(adapter_class)
            @adapters[adapter_name] = adapter_class
          end
          @config['llms'].each do |llm_name,llm_config|
            adapter_class = @adapters[llm_config['adapter']]
            @llms[llm_name]=adapter_class.new(llm_config)
          end
          @current_llm = @config['default_llm'] if @config['default_llm']
          Dir.glob(File.join(@config['template_path'], '*.erb')).each do |file|
            template_name = file.gsub(@config['template_path']+"/","").gsub("\.erb","")
            @templates[template_name] = PromptTemplate.new(file)
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
        Dir.glob(File.join(@config['worker_path'], '*.rb')).each do |file|
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
          result = worker.execute(params)
          SmartPrompt.logger.info "Worker #{worker_name} executed successfully"
          result
        rescue => e
          SmartPrompt.logger.error "Error executing worker #{worker_name}: #{e.message}"
          SmartPrompt.logger.debug e.backtrace.join("\n")
          raise
        end
      end
  
      private
  
      def get_worker(worker_name)
        SmartPrompt.logger.info "Creating worker instance for: #{worker_name}"
        Worker.new(worker_name, self)
      end
    end
  end