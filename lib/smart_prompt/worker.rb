module SmartPrompt
  class Worker
    attr_reader :name, :config_file

    def initialize(name, engine)
      @name = name
      @engine = engine
      @config = engine.config
      @code = self.class.workers[name]
    end

    def execute(params = {})
      conversation = Conversation.new(@engine)
      context = WorkerContext.new(conversation, params, @engine)
      context.instance_eval(&@code)
    end

    class << self
      def workers
        @workers ||= {}
      end

      def define(name, &block)
        workers[name] = block
      end
    end
  end

  class WorkerContext
    def initialize(conversation, params, engine)
      @conversation = conversation
      @params = params
      @engine = engine
    end

    def method_missing(method, *args, &block)
      if @conversation.respond_to?(method)
        @conversation.send(method, *args, &block)
      else
        super
      end
    end

    def respond_to_missing?(method, include_private = false)
      @conversation.respond_to?(method) || super
    end

    def params
      @params
    end

    def call_worker(worker_name, params = {})
      worker = Worker.new(worker_name, @engine)
      worker.execute(params)
    end
  end
end