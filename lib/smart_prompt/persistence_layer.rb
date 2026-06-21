require 'json'
require 'fileutils'
require 'thread'

module SmartPrompt
  # AsyncWriter handles asynchronous write operations to avoid blocking
  class AsyncWriter
    def initialize
      @queue = Queue.new
      @worker_thread = nil
      @running = false
      @mutex = Mutex.new
    end

    # Enqueue a block to be executed asynchronously
    def enqueue(&block)
      ensure_worker_running
      @queue << block
    end

    # Stop the worker thread gracefully
    def stop
      @mutex.synchronize do
        @running = false
      end
      @queue << :stop if @worker_thread
      @worker_thread&.join
    end

    # Check if the worker is running
    def running?
      @mutex.synchronize { @running }
    end

    private

    def ensure_worker_running
      @mutex.synchronize do
        return if @running

        @running = true
        @worker_thread = Thread.new { worker_loop }
      end
    end

    def worker_loop
      loop do
        task = @queue.pop
        break if task == :stop

        begin
          task.call if task.respond_to?(:call)
        rescue => e
          SmartPrompt.logger.error "AsyncWriter task failed: #{e.message}\n#{e.backtrace.join("\n")}"
        end
      end
    rescue => e
      SmartPrompt.logger.error "AsyncWriter worker loop crashed: #{e.message}"
    ensure
      @mutex.synchronize { @running = false }
    end
  end

  # PersistenceLayer handles saving and loading session data to/from disk
  class PersistenceLayer
    attr_reader :storage_path, :enabled

    def initialize(config = {})
      @backend = config[:backend] || :filesystem
      @storage_path = config[:storage_path] || "./history_data"
      @async_writer = AsyncWriter.new
      @enabled = config[:enabled] != false
      @async = config[:async] != false

      # Create storage directory if persistence is enabled
      ensure_storage_directory if @enabled
    end

    # Save a session synchronously
    def save(session)
      return unless @enabled

      file_path = session_file_path(session.id)
      data = serialize_session(session)

      File.write(file_path, data)
      SmartPrompt.logger.info "Session #{session.id} saved to #{file_path}"
    rescue => e
      SmartPrompt.logger.error "Failed to save session #{session.id}: #{e.message}"
      # Continue operating with in-memory storage (fallback behavior)
    end

    # Save a session asynchronously
    def save_async(session)
      return unless @enabled

      if @async
        @async_writer.enqueue do
          save(session)
        end
      else
        # If async is disabled, fall back to synchronous save
        save(session)
      end
    end

    # Load a session from disk
    def load(session_id)
      return nil unless @enabled

      file_path = session_file_path(session_id)
      return nil unless File.exist?(file_path)

      data = File.read(file_path)
      session_data = deserialize_session(data)
      
      SmartPrompt.logger.info "Session #{session_id} loaded from #{file_path}"
      session_data
    rescue => e
      SmartPrompt.logger.error "Failed to load session #{session_id}: #{e.message}"
      nil
    end

    # Delete a session from disk
    def delete(session_id)
      return unless @enabled

      file_path = session_file_path(session_id)
      if File.exist?(file_path)
        File.delete(file_path)
        SmartPrompt.logger.info "Session #{session_id} deleted from disk"
      end
    rescue => e
      SmartPrompt.logger.error "Failed to delete session #{session_id}: #{e.message}"
    end

    # Check if a session exists on disk
    def exists?(session_id)
      return false unless @enabled

      file_path = session_file_path(session_id)
      File.exist?(file_path)
    end

    # List all session IDs stored on disk
    def list_sessions
      return [] unless @enabled

      Dir.glob(File.join(@storage_path, "*.json")).map do |file|
        File.basename(file, ".json")
      end
    rescue => e
      SmartPrompt.logger.error "Failed to list sessions: #{e.message}"
      []
    end

    # Stop the async writer gracefully
    def shutdown
      @async_writer.stop if @async_writer
    end

    private

    # Ensure the storage directory exists
    def ensure_storage_directory
      return if Dir.exist?(@storage_path)
      
      FileUtils.mkdir_p(@storage_path)
      SmartPrompt.logger.info "Created storage directory: #{@storage_path}"
    rescue => e
      SmartPrompt.logger.error "Failed to create storage directory #{@storage_path}: #{e.message}"
      @enabled = false
    end

    # Get the file path for a session
    def session_file_path(session_id)
      File.join(@storage_path, "#{session_id}.json")
    end

    # Serialize a session to JSON
    def serialize_session(session)
      JSON.pretty_generate({
        id: session.id,
        messages: session.messages.map(&:to_h),
        metadata: session.metadata,
        created_at: session.created_at.iso8601,
        updated_at: session.updated_at.iso8601,
        config: session.config
      })
    end

    # Deserialize session data from JSON
    def deserialize_session(data)
      JSON.parse(data, symbolize_names: true)
    end
  end
end
