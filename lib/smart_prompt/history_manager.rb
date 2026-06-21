require 'thread'

module SmartPrompt
  # HistoryManager manages multiple conversation sessions with isolation and configuration
  class HistoryManager
    attr_reader :config

    def initialize(config = {})
      @config = default_config.merge(config)
      @session_cache = LRUCache.new(@config[:cache_size])
      @persistence = PersistenceLayer.new(@config[:persistence] || {})
      @cleanup_thread = nil
      @cleanup_mutex = Mutex.new
      @session_mutex = Mutex.new  # Add mutex for session creation
      @shutdown_requested = false
      
      # Initialize metrics tracking
      @metrics = {
        sessions_created: 0,
        sessions_deleted: 0,
        messages_added: 0,
        context_retrievals: 0,
        cache_hits: 0,
        cache_misses: 0,
        persistence_errors: 0,
        compression_operations: 0,
        tokens_saved_by_compression: 0
      }
      @metrics_mutex = Mutex.new
      
      # Log initialization
      log_info "HistoryManager initialized with cache_size=#{@config[:cache_size]}"
      
      # Start cleanup thread if auto_cleanup is enabled
      start_cleanup_thread if @config[:cleanup][:auto_cleanup]
    end

    # Get or create a session
    def get_session(session_id, options = {})
      # Check if session is in cache
      session = @session_cache.get(session_id)
      
      if session
        # Cache hit
        increment_metric(:cache_hits)
        log_debug "Session #{session_id} retrieved from cache"
        return session
      end
      
      # Cache miss - use mutex to prevent race conditions
      @session_mutex.synchronize do
        # Double-check after acquiring lock
        session = @session_cache.get(session_id)
        return session if session
        
        # Cache miss
        increment_metric(:cache_misses)
        log_debug "Session #{session_id} not in cache, loading or creating"
        
        # Try to load from persistence first
        session_data = @persistence.load(session_id)
        
        if session_data
          # Restore session from persisted data
          session = restore_session(session_data, options)
          log_info "Session #{session_id} restored from persistence (#{session.message_count} messages, #{session.total_tokens} tokens)"
        else
          # Create new session
          session_config = @config[:session_defaults].merge(options)
          session = Session.new(session_id, session_config)
          increment_metric(:sessions_created)
          log_info "Session #{session_id} created with config: max_messages=#{session_config[:max_messages]}, max_tokens=#{session_config[:max_tokens]}, strategy=#{session_config[:context_strategy]}"
        end
        
        # Add to cache (will handle eviction if needed)
        @session_cache.put(session_id, session)
        
        session
      end
    end

    # Add a message to a session
    def add_message(session_id, message, options = {})
      begin
        session = get_session(session_id, options)
        msg = session.add_message(message)
        
        increment_metric(:messages_added)
        log_debug "Message added to session #{session_id}: role=#{msg.role}, tokens=#{msg.token_count}"
        
        # Persist the session asynchronously
        begin
          @persistence.save_async(session)
        rescue => e
          increment_metric(:persistence_errors)
          log_error "Persistence failed for session #{session_id}", e
          # Continue without persistence
        end
        
        session
      rescue => e
        log_error "Failed to add message to session #{session_id}", e
        raise HistoryManagerError, "Failed to add message: #{e.message}"
      end
    end

    # Get context (messages) from a session
    def get_context(session_id, max_tokens = nil, strategy = nil)
      begin
        session = get_session(session_id)
        messages = session.get_messages
        
        increment_metric(:context_retrievals)
        
        # If no token limit specified, return all messages
        if max_tokens.nil?
          log_debug "Context retrieved for session #{session_id}: all #{messages.count} messages (#{session.total_tokens} tokens)"
          return messages
        end
        
        # Simple token limiting for now (will be enhanced with strategies later)
        selected_messages = []
        current_tokens = 0
        
        # Always include system messages first
        system_messages = messages.select(&:system_message?)
        system_messages.each do |msg|
          selected_messages << msg
          current_tokens += msg.token_count || 0
        end
        
        # Add non-system messages from most recent, respecting token limit
        non_system_messages = messages.reject(&:system_message?)
        non_system_messages.reverse_each do |msg|
          msg_tokens = msg.token_count || 0
          if current_tokens + msg_tokens <= max_tokens
            selected_messages << msg
            current_tokens += msg_tokens
          else
            break
          end
        end
        
        # Return in chronological order
        result = selected_messages.sort_by(&:timestamp)
        
        log_debug "Context selected for session #{session_id}: #{result.count}/#{messages.count} messages, #{current_tokens}/#{max_tokens} tokens"
        
        result
      rescue => e
        log_error "Failed to get context for session #{session_id}", e
        raise HistoryManagerError, "Failed to get context: #{e.message}"
      end
    end

    # Clear a session's history
    def clear_session(session_id, keep_system_messages: true)
      begin
        session = get_session(session_id)
        messages_before = session.message_count
        session.clear(preserve_system: keep_system_messages)
        messages_after = session.message_count
        
        log_info "Session #{session_id} cleared: #{messages_before} -> #{messages_after} messages (keep_system=#{keep_system_messages})"
      rescue => e
        log_error "Failed to clear session #{session_id}", e
        raise HistoryManagerError, "Failed to clear session: #{e.message}"
      end
    end

    # Delete a session completely
    def delete_session(session_id)
      begin
        @session_cache.delete(session_id)
        
        # Delete from persistence
        @persistence.delete(session_id)
        
        increment_metric(:sessions_deleted)
        log_info "Session #{session_id} deleted"
      rescue => e
        log_error "Failed to delete session #{session_id}", e
        raise HistoryManagerError, "Failed to delete session: #{e.message}"
      end
    end

    # Export a session's data
    def export_session(session_id, format: :json)
      begin
        session = get_session(session_id)
        result = case format
        when :json
          require 'json'
          JSON.pretty_generate(session.to_h)
        when :hash
          session.to_h
        else
          raise ArgumentError, "Unsupported format: #{format}"
        end
        
        log_info "Session #{session_id} exported in #{format} format"
        result
      rescue => e
        log_error "Failed to export session #{session_id}", e
        raise HistoryManagerError, "Failed to export session: #{e.message}"
      end
    end

    # Search messages in a session
    def search_messages(session_id, query, options = {})
      begin
        session = get_session(session_id)
        messages = session.get_messages
        
        results = messages.select do |msg|
          msg.content.to_s.include?(query)
        end
        
        log_debug "Search in session #{session_id} for '#{query}': #{results.count}/#{messages.count} matches"
        results
      rescue => e
        log_error "Failed to search messages in session #{session_id}", e
        raise HistoryManagerError, "Failed to search messages: #{e.message}"
      end
    end

    # Get statistics for a session or all sessions
    def get_stats(session_id = nil)
      begin
        if session_id
          # Session-specific statistics
          session = get_session(session_id)
          {
            session_id: session_id,
            message_count: session.message_count,
            total_tokens: session.total_tokens,
            created_at: session.created_at,
            updated_at: session.updated_at,
            config: session.config
          }
        else
          # System-wide statistics
          @metrics_mutex.synchronize do
            cache_total = @metrics[:cache_hits] + @metrics[:cache_misses]
            cache_hit_rate = cache_total > 0 ? @metrics[:cache_hits].to_f / cache_total : 0.0
            
            {
              # Session metrics
              active_sessions: @session_cache.size,
              sessions_created: @metrics[:sessions_created],
              sessions_deleted: @metrics[:sessions_deleted],
              
              # Message metrics
              total_messages: @session_cache.values.sum(&:message_count),
              messages_added: @metrics[:messages_added],
              messages_per_session_avg: @session_cache.size > 0 ? 
                @session_cache.values.sum(&:message_count).to_f / @session_cache.size : 0.0,
              
              # Token metrics
              total_tokens: @session_cache.values.sum(&:total_tokens),
              tokens_per_session_avg: @session_cache.size > 0 ?
                @session_cache.values.sum(&:total_tokens).to_f / @session_cache.size : 0.0,
              tokens_per_message_avg: @session_cache.values.sum(&:message_count) > 0 ?
                @session_cache.values.sum(&:total_tokens).to_f / @session_cache.values.sum(&:message_count) : 0.0,
              
              # Cache metrics
              cache_size: @config[:cache_size],
              cache_hits: @metrics[:cache_hits],
              cache_misses: @metrics[:cache_misses],
              cache_hit_rate: cache_hit_rate,
              
              # Operation metrics
              context_retrievals: @metrics[:context_retrievals],
              
              # Compression metrics
              compression_operations: @metrics[:compression_operations],
              tokens_saved_by_compression: @metrics[:tokens_saved_by_compression],
              
              # Error metrics
              persistence_errors: @metrics[:persistence_errors]
            }
          end
        end
      rescue => e
        log_error "Failed to get statistics#{session_id ? " for session #{session_id}" : ""}", e
        raise HistoryManagerError, "Failed to get statistics: #{e.message}"
      end
    end

    # Check if a session exists
    def session_exists?(session_id)
      @session_cache.key?(session_id)
    end

    # Get list of all session IDs
    def session_ids
      @session_cache.keys
    end

    # Get the least recently used session ID
    def lru_session_id
      @session_cache.lru_key
    end
    
    # Export metrics in a standard format (Prometheus-style)
    def export_metrics(format: :prometheus)
      stats = get_stats
      
      case format
      when :prometheus
        export_prometheus_metrics(stats)
      when :json
        require 'json'
        JSON.pretty_generate(stats)
      when :hash
        stats
      else
        raise ArgumentError, "Unsupported format: #{format}"
      end
    end

    # Shutdown the history manager gracefully
    def shutdown
      @shutdown_requested = true
      
      # Stop cleanup thread
      if @cleanup_thread
        @cleanup_thread.join(5) # Wait up to 5 seconds for thread to finish
        @cleanup_thread = nil
      end
      
      @persistence.shutdown if @persistence
    end
    
    # Manually trigger cleanup of expired sessions
    def cleanup_expired_sessions
      return unless @config[:cleanup]
      
      session_ttl = @config[:cleanup][:session_ttl]
      cleanup_callback = @config[:cleanup][:cleanup_callback]
      
      expired_session_ids = []
      
      @cleanup_mutex.synchronize do
        @session_cache.keys.each do |session_id|
          session = @session_cache.get(session_id)
          next unless session
          
          # Check if session has expired based on TTL
          age = Time.now - session.updated_at
          should_cleanup = age > session_ttl
          
          # If custom callback is provided, use it to determine cleanup
          if cleanup_callback && cleanup_callback.respond_to?(:call)
            should_cleanup = cleanup_callback.call(session, age)
          end
          
          if should_cleanup
            expired_session_ids << session_id
            log_debug "Session #{session_id} marked for cleanup (age: #{age.to_i}s, ttl: #{session_ttl}s)"
          end
        end
        
        # Remove expired sessions
        expired_session_ids.each do |session_id|
          delete_session(session_id)
        end
      end
      
      if expired_session_ids.any?
        log_info "Cleanup completed: #{expired_session_ids.count} expired sessions removed"
      else
        log_debug "Cleanup completed: no expired sessions found"
      end
      
      expired_session_ids
    end

    private

    # Restore a session from persisted data
    def restore_session(session_data, options = {})
      session_config = @config[:session_defaults].merge(options)
      session = Session.new(session_data[:id], session_config)
      
      # Restore metadata
      session.instance_variable_set(:@metadata, session_data[:metadata] || {})
      
      # Restore timestamps
      session.instance_variable_set(:@created_at, Time.parse(session_data[:created_at])) if session_data[:created_at]
      session.instance_variable_set(:@updated_at, Time.parse(session_data[:updated_at])) if session_data[:updated_at]
      
      # Restore messages
      if session_data[:messages]
        session_data[:messages].each do |msg_data|
          session.add_message(msg_data)
        end
      end
      
      session
    end

    # Start the cleanup thread
    def start_cleanup_thread
      return if @cleanup_thread && @cleanup_thread.alive?
      
      cleanup_interval = @config[:cleanup][:cleanup_interval]
      
      log_info "Starting cleanup thread with interval=#{cleanup_interval}s, ttl=#{@config[:cleanup][:session_ttl]}s"
      
      @cleanup_thread = Thread.new do
        loop do
          break if @shutdown_requested
          
          begin
            sleep(cleanup_interval)
            break if @shutdown_requested
            
            # Perform cleanup
            cleanup_expired_sessions
          rescue => e
            # Log error but keep thread running
            log_error "Cleanup thread error", e
          end
        end
        
        log_info "Cleanup thread stopped"
      end
      
      @cleanup_thread
    end

    # Default configuration
    def default_config
      {
        cache_size: 100,
        session_defaults: {
          max_messages: 100,
          max_tokens: 4000,
          context_strategy: :sliding_window,
          preserve_system_messages: true
        },
        persistence: {
          enabled: true,
          backend: :filesystem,
          storage_path: "./history_data",
          async: true
        },
        cleanup: {
          auto_cleanup: false,
          cleanup_interval: 3600,  # 1 hour in seconds
          session_ttl: 86400,      # 24 hours in seconds
          cleanup_callback: nil
        },
        monitoring: {
          enabled: true,
          log_level: :info
        }
      }
    end
    
    # Increment a metric counter
    def increment_metric(metric_name, amount = 1)
      @metrics_mutex.synchronize do
        @metrics[metric_name] ||= 0
        @metrics[metric_name] += amount
      end
    end
    
    # Logging helper methods
    def log_info(message)
      return unless monitoring_enabled?
      return unless log_level_enabled?(:info)
      SmartPrompt.logger.info "[HistoryManager] #{message}"
    end
    
    def log_debug(message)
      return unless monitoring_enabled?
      return unless log_level_enabled?(:debug)
      SmartPrompt.logger.debug "[HistoryManager] #{message}"
    end
    
    def log_warn(message)
      return unless monitoring_enabled?
      SmartPrompt.logger.warn "[HistoryManager] #{message}"
    end
    
    def log_error(message, exception = nil)
      return unless monitoring_enabled?
      
      error_msg = "[HistoryManager] #{message}"
      if exception
        error_msg += ": #{exception.class.name} - #{exception.message}"
        error_msg += "\n#{exception.backtrace.first(5).join("\n")}" if exception.backtrace
      end
      
      SmartPrompt.logger.error error_msg
    end
    
    def monitoring_enabled?
      @config[:monitoring] && @config[:monitoring][:enabled] != false
    end
    
    def log_level_enabled?(level)
      return true unless @config[:monitoring]
      
      configured_level = @config[:monitoring][:log_level] || :info
      # Convert to symbol if it's a string
      configured_level = configured_level.to_sym if configured_level.is_a?(String)
      level_priority = { debug: 0, info: 1, warn: 2, error: 3 }
      
      # Return true if either level is not in the priority hash (to avoid nil comparison)
      return true unless level_priority.key?(level) && level_priority.key?(configured_level)
      
      level_priority[level] >= level_priority[configured_level]
    end
    
    # Export metrics in Prometheus format
    def export_prometheus_metrics(stats)
      lines = []
      
      # Session metrics
      lines << "# HELP smart_prompt_active_sessions Number of active sessions in cache"
      lines << "# TYPE smart_prompt_active_sessions gauge"
      lines << "smart_prompt_active_sessions #{stats[:active_sessions]}"
      
      lines << "# HELP smart_prompt_sessions_created_total Total number of sessions created"
      lines << "# TYPE smart_prompt_sessions_created_total counter"
      lines << "smart_prompt_sessions_created_total #{stats[:sessions_created]}"
      
      lines << "# HELP smart_prompt_sessions_deleted_total Total number of sessions deleted"
      lines << "# TYPE smart_prompt_sessions_deleted_total counter"
      lines << "smart_prompt_sessions_deleted_total #{stats[:sessions_deleted]}"
      
      # Message metrics
      lines << "# HELP smart_prompt_total_messages Total number of messages across all sessions"
      lines << "# TYPE smart_prompt_total_messages gauge"
      lines << "smart_prompt_total_messages #{stats[:total_messages]}"
      
      lines << "# HELP smart_prompt_messages_added_total Total number of messages added"
      lines << "# TYPE smart_prompt_messages_added_total counter"
      lines << "smart_prompt_messages_added_total #{stats[:messages_added]}"
      
      lines << "# HELP smart_prompt_messages_per_session_avg Average messages per session"
      lines << "# TYPE smart_prompt_messages_per_session_avg gauge"
      lines << "smart_prompt_messages_per_session_avg #{stats[:messages_per_session_avg]}"
      
      # Token metrics
      lines << "# HELP smart_prompt_total_tokens Total number of tokens across all sessions"
      lines << "# TYPE smart_prompt_total_tokens gauge"
      lines << "smart_prompt_total_tokens #{stats[:total_tokens]}"
      
      lines << "# HELP smart_prompt_tokens_per_session_avg Average tokens per session"
      lines << "# TYPE smart_prompt_tokens_per_session_avg gauge"
      lines << "smart_prompt_tokens_per_session_avg #{stats[:tokens_per_session_avg]}"
      
      lines << "# HELP smart_prompt_tokens_per_message_avg Average tokens per message"
      lines << "# TYPE smart_prompt_tokens_per_message_avg gauge"
      lines << "smart_prompt_tokens_per_message_avg #{stats[:tokens_per_message_avg]}"
      
      # Cache metrics
      lines << "# HELP smart_prompt_cache_hits_total Total number of cache hits"
      lines << "# TYPE smart_prompt_cache_hits_total counter"
      lines << "smart_prompt_cache_hits_total #{stats[:cache_hits]}"
      
      lines << "# HELP smart_prompt_cache_misses_total Total number of cache misses"
      lines << "# TYPE smart_prompt_cache_misses_total counter"
      lines << "smart_prompt_cache_misses_total #{stats[:cache_misses]}"
      
      lines << "# HELP smart_prompt_cache_hit_rate Cache hit rate (0.0-1.0)"
      lines << "# TYPE smart_prompt_cache_hit_rate gauge"
      lines << "smart_prompt_cache_hit_rate #{stats[:cache_hit_rate]}"
      
      # Operation metrics
      lines << "# HELP smart_prompt_context_retrievals_total Total number of context retrievals"
      lines << "# TYPE smart_prompt_context_retrievals_total counter"
      lines << "smart_prompt_context_retrievals_total #{stats[:context_retrievals]}"
      
      # Compression metrics
      lines << "# HELP smart_prompt_compression_operations_total Total number of compression operations"
      lines << "# TYPE smart_prompt_compression_operations_total counter"
      lines << "smart_prompt_compression_operations_total #{stats[:compression_operations]}"
      
      lines << "# HELP smart_prompt_tokens_saved_by_compression_total Total tokens saved by compression"
      lines << "# TYPE smart_prompt_tokens_saved_by_compression_total counter"
      lines << "smart_prompt_tokens_saved_by_compression_total #{stats[:tokens_saved_by_compression]}"
      
      # Error metrics
      lines << "# HELP smart_prompt_persistence_errors_total Total number of persistence errors"
      lines << "# TYPE smart_prompt_persistence_errors_total counter"
      lines << "smart_prompt_persistence_errors_total #{stats[:persistence_errors]}"
      
      lines.join("\n")
    end
  end
end
