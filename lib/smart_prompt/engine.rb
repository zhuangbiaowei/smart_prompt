module SmartPrompt
    class Engine
      attr_reader :config_file, :config, :adapters, :current_adapter, :templates
      def initialize(config_file)
        @config_file = config_file
        @adapters={}
        @templates={}
        load_config(config_file)
      end

      def load_config(config_file)
        @config_file = config_file
        @config = YAML.load_file(config_file)
        @config['adapters'].each do |adapter_name, adapter_config|
          adapter_class = SmartPrompt.const_get("#{adapter_name.capitalize}Adapter")          
          @adapters[adapter_name] = adapter_class.new(adapter_config)
        end
        @current_adapter = @config['default_adapter'] if @config['default_adapter']        
        @config['templates'].each do |template_name, template_file|
          @templates[template_name] = PromptTemplate.new(template_file)
        end
        load_workers
      end

      def load_workers
        Dir.glob(File.join(@config['worker_path'], '*.rb')).each do |file|
          require(file)
        end
      end
        
      def call_worker(worker_name, params = {})
        worker = get_worker(worker_name)
        worker.execute(params)
      end
  
      private
  
      def get_worker(worker_name)
        worker = Worker.new(worker_name, self)
      end
    end
  end