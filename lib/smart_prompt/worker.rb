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
      @transient_messages = []
    end

    # Add a user prompt to the current request only, without persisting it to
    # HistoryManager. Progress, retry notes and hard-intervention text are
    # snapshots, not conversation history; persisting one large user message per
    # round would evict the assistant/tool evidence we need to retain.
    def transient_prompt(content)
      @transient_messages << content
      @conversation.prompt(content, with_history: false)
    end

    def method_missing(method, *args, &block)
      if @conversation.respond_to?(method)
        if method == :send_msg
          send_params = params
          if params[:with_history] && !@transient_messages.empty?
            # The default send path would send *only* history_messages when
            # with_history=true, silently dropping the transient prompt just
            # added to @conversation.messages. Merge both sources for this
            # request and use the ordinary send path. When there is no transient
            # prompt, keep the original with_history send so the persisted
            # prompt pattern is not duplicated.
            prepare_transient_history_request!
            send_params = params.merge(with_history: false)
          end
          if @proc.nil?
            @conversation.send_msg(send_params)
          else
            @conversation.send_msg_by_stream(send_params, &@proc)
          end
        elsif method == :sys_msg
          # The system message always belongs to the current request. Its
          # durable session copy is upserted by Conversation#sys_msg so a worker
          # loop never accumulates one preserved system message per round.
          @conversation.sys_msg(*args, with_history: params[:with_history])
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
      method == :transient_prompt || @conversation.respond_to?(method) || super
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

    private

    # Merge the persisted session history with the transient prompts recorded
    # this round. Persisted prompts stay in history_messages and are therefore
    # already part of the request, so only the transient user messages need to
    # be appended to avoid duplication.
    def prepare_transient_history_request!
      current = Array(@conversation.messages)
      history = session_history
      SmartPrompt.logger&.info(
        "[SmartPrompt history] session=#{@params[:session_id]} " \
        "messages=#{history.size} roles=#{history.map { |message| message_role(message) }.tally}"
      )
      system = current.select { |message| message_role(message) == "system" }
      historical_turns = history.reject { |message| message_role(message) == "system" }
      transient_turn = @transient_messages.map { |content| { role: "user", content: content } }
      @conversation.instance_variable_set(:@messages, system + historical_turns + transient_turn)
    end

    def session_history
      if @engine.respond_to?(:history_manager) && @engine.history_manager
        sid = @params[:session_id]
        raise ArgumentError, "history requires an explicit session_id" if sid.to_s.strip.empty?

        @engine.history_manager.get_context(sid).map(&:to_h)
      elsif @engine.respond_to?(:history_messages)
        Array(@engine.history_messages)
      else
        []
      end
    end

    def message_role(message)
      return message.role.to_s if message.respond_to?(:role)

      (message[:role] || message["role"]).to_s
    end
  end
end
