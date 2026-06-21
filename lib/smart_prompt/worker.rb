module SmartPrompt
  class Worker
    attr_reader :name, :config_file, :conversation

    def initialize(name, engine)
      SmartPrompt.logger.info "Create worker's name is #{name}"
      @name = name
      @engine = engine
      @config = engine.config
      @code = self.class.workers[name]
    end

    def execute(params = {})
      # Generate default session ID if using history and no session_id provided.
      # (Do NOT default to a literal "default" here — that would make every
      # history-using worker share one session and leave the worker-name branch
      # below as dead code, breaking per-worker session isolation.)
      session_id = params[:session_id]
      if params[:with_history] && !session_id && @engine.history_manager
        session_id = "worker_#{@name}_#{Time.now.to_i}"
        SmartPrompt.logger.info "Generated default session ID: #{session_id}"
      end
      if @conversation.nil? || @conversation.session_id != session_id
        @conversation = Conversation.new(@engine, params[:tools], session_id)
      end
      context = WorkerContext.new(@conversation, params, @engine)
      context.instance_eval(&@code)
    end

    def execute_by_stream(params = {}, &proc)
      # Generate default session ID if using history and no session_id provided
      session_id = params[:session_id]
      if params[:with_history] && !session_id && @engine.history_manager
        session_id = "worker_#{@name}_#{Time.now.to_i}"
        SmartPrompt.logger.info "Generated default session ID: #{session_id}"
      end

      @conversation = Conversation.new(@engine, params[:tools], session_id)
      context = WorkerContext.new(@conversation, params, @engine, proc)
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
    def initialize(conversation, params, engine, proc = nil)
      @conversation = conversation
      @params = params
      @engine = engine
      @proc = proc
    end

    def method_missing(method, *args, &block)
      if @conversation.respond_to?(method)
        if method == :send_msg
          if @proc == nil
            @conversation.send_msg(params)
          else
            @conversation.send_msg_by_stream(params, &@proc)
          end
        elsif method == :sys_msg
          @conversation.sys_msg(*args)
        elsif method == :prompt
          @conversation.prompt(*args, with_history: params[:with_history])
        else
          @conversation.send(method, *args, &block)
        end
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

    def proc
      @proc
    end

    # Expose the engine so workers can reach a configured adapter directly (e.g.
    # `engine.llms["..."]`) for methods Conversation doesn't delegate, such as
    # generate_video / synthesize_to_file / transcribe_audio.
    def engine
      @engine
    end

    def call_worker(worker_name, params = {})
      worker = Worker.new(worker_name, @engine)
      worker.execute(params)
    end

    def call_worker_by_stream(worker_name, params = {}, proc)
      worker = Worker.new(worker_name, @engine)
      worker.execute_by_stream(params, proc)
    end
  end
end
