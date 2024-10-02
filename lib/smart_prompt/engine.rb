module SmartPrompt
    class Engine
      attr_reader :config_file, :config, :adapters, :current_adapter, :llms, :templates
      def initialize(config_file)
        @config_file = config_file
        @adapters={}
        @llms={}
        @templates={}
        load_config(config_file)
      end

      def load_config(config_file)
        @config_file = config_file
        @config = YAML.load_file(config_file)
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