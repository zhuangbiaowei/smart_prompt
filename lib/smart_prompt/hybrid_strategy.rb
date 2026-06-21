require_relative 'context_strategy'
require_relative 'sliding_window_strategy'
require_relative 'relevance_based_strategy'
require_relative 'summary_based_strategy'

module SmartPrompt
  # HybridStrategy implements a flexible context selection strategy that
  # combines multiple strategies for optimal results
  # 
  # This strategy supports two modes:
  # - Adaptive mode: Automatically selects the best strategy based on message count
  # - Combined mode: Merges results from multiple strategies
  # 
  # Adaptive mode selection logic:
  # - < 20 messages: Use SlidingWindowStrategy (simple and efficient)
  # - 20-50 messages: Use RelevanceBasedStrategy (balance recency and relevance)
  # - > 50 messages: Use SummaryBasedStrategy (compress older messages)
  # 
  # Combined mode:
  # - Runs multiple strategies and merges their results
  # - Removes duplicates and sorts by importance
  # - Provides comprehensive context from different perspectives
  class HybridStrategy
    include ContextStrategy

    # Initialize the hybrid strategy
    # @param config [Hash] Configuration options
    # @option config [Symbol] :mode (:adaptive) Strategy mode - :adaptive or :combined
    # @option config [Hash] :sliding_window ({}) Configuration for SlidingWindowStrategy
    # @option config [Hash] :relevance_based ({}) Configuration for RelevanceBasedStrategy
    # @option config [Hash] :summary_based ({}) Configuration for SummaryBasedStrategy
    # @option config [Integer] :adaptive_threshold_low (20) Message count threshold for adaptive mode (low)
    # @option config [Integer] :adaptive_threshold_high (50) Message count threshold for adaptive mode (high)
    def initialize(config = {})
      @mode = config[:mode] || :adaptive
      @adaptive_threshold_low = config[:adaptive_threshold_low] || 20
      @adaptive_threshold_high = config[:adaptive_threshold_high] || 50

      # Initialize sub-strategies with their configurations
      @sliding_window = SlidingWindowStrategy.new(config[:sliding_window] || {})
      @relevance_based = RelevanceBasedStrategy.new(config[:relevance_based] || {})
      @summary_based = SummaryBasedStrategy.new(config[:summary_based] || {})

      # Validate mode
      unless [:adaptive, :combined].include?(@mode)
        raise ArgumentError, "Invalid mode: #{@mode}. Must be :adaptive or :combined"
      end
    end

    # Select messages using hybrid approach
    # @param messages [Array<Message>] All messages in the session
    # @param max_tokens [Integer, nil] Maximum token limit for selected messages
    # @param current_message [Message, nil] The current message for relevance calculation
    # @return [Array<Message>] Selected messages
    def select_messages(messages, max_tokens, current_message = nil)
      return [] if messages.nil? || messages.empty?

      case @mode
      when :adaptive
        select_adaptive(messages, max_tokens, current_message)
      when :combined
        select_combined(messages, max_tokens, current_message)
      else
        # Fallback to sliding window if mode is somehow invalid
        @sliding_window.select_messages(messages, max_tokens, current_message)
      end
    end

    # Determine if compression should be triggered
    # Uses the most conservative threshold from all strategies
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if any strategy recommends compression
    def should_compress?(session)
      return false if session.nil?
      
      # In adaptive mode, use the threshold of the currently selected strategy
      if @mode == :adaptive
        message_count = session.message_count
        
        if message_count < @adaptive_threshold_low
          @sliding_window.should_compress?(session)
        elsif message_count < @adaptive_threshold_high
          @relevance_based.should_compress?(session)
        else
          @summary_based.should_compress?(session)
        end
      else
        # In combined mode, compress if any strategy recommends it
        @sliding_window.should_compress?(session) ||
          @relevance_based.should_compress?(session) ||
          @summary_based.should_compress?(session)
      end
    end

    private

    # Select messages using adaptive strategy selection
    # Chooses the best strategy based on message count
    # @param messages [Array<Message>] All messages
    # @param max_tokens [Integer, nil] Maximum token limit
    # @param current_message [Message, nil] Current message for relevance
    # @return [Array<Message>] Selected messages
    def select_adaptive(messages, max_tokens, current_message)
      message_count = messages.count

      # Select strategy based on message count thresholds
      strategy = if message_count < @adaptive_threshold_low
        # For small conversations, use simple sliding window
        @sliding_window
      elsif message_count < @adaptive_threshold_high
        # For medium conversations, use relevance-based selection
        @relevance_based
      else
        # For large conversations, use summarization
        @summary_based
      end

      # Log the selected strategy for debugging
      log_debug "Adaptive mode: selected #{strategy.class.name} for #{message_count} messages (thresholds: <#{@adaptive_threshold_low}, <#{@adaptive_threshold_high})"

      # Delegate to the selected strategy
      strategy.select_messages(messages, max_tokens, current_message)
    end

    # Select messages by combining results from multiple strategies
    # Merges results and removes duplicates
    # @param messages [Array<Message>] All messages
    # @param max_tokens [Integer, nil] Maximum token limit
    # @param current_message [Message, nil] Current message for relevance
    # @return [Array<Message>] Selected messages
    def select_combined(messages, max_tokens, current_message)
      # Get results from each strategy (without token limit initially)
      sliding_result = @sliding_window.select_messages(messages, nil, current_message)
      relevance_result = @relevance_based.select_messages(messages, nil, current_message)
      
      # For summary-based, only include if we have many messages
      # to avoid premature summarization
      summary_result = if messages.count > @adaptive_threshold_high
        @summary_based.select_messages(messages, nil, current_message)
      else
        []
      end

      # Combine all results and remove duplicates
      # Use message object_id to identify unique messages
      combined = (sliding_result + relevance_result + summary_result).uniq

      log_debug "Combined mode: merged #{sliding_result.count} + #{relevance_result.count} + #{summary_result.count} = #{combined.count} unique messages"

      # Sort by timestamp to maintain conversation order
      combined = combined.sort_by(&:timestamp)

      # Trim to token limit if specified
      result = max_tokens ? trim_to_token_limit(combined, max_tokens) : combined
      
      if max_tokens && result.count < combined.count
        tokens_before = combined.sum { |m| m.token_count || 0 }
        tokens_after = result.sum { |m| m.token_count || 0 }
        log_debug "Combined mode: trimmed to token limit #{max_tokens}: #{combined.count} -> #{result.count} messages, #{tokens_before} -> #{tokens_after} tokens"
      end
      
      result
    end

    # Trim messages to fit within token limit
    # Prioritizes messages with higher importance scores
    # @param messages [Array<Message>] Messages to trim
    # @param max_tokens [Integer] Maximum token limit
    # @return [Array<Message>] Trimmed messages
    def trim_to_token_limit(messages, max_tokens)
      return messages unless max_tokens
      return [] if messages.empty?

      # Separate system messages (always keep) from others
      system_messages = messages.select(&:system_message?)
      other_messages = messages.reject(&:system_message?)

      # Start with system messages
      selected = []
      total = 0

      system_messages.each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected << msg
          total += msg_tokens
        else
          SmartPrompt.logger.warn "Token limit too small to fit all system messages"
          break
        end
      end

      # Sort other messages by importance score (if available) or recency
      sorted_others = other_messages.sort_by do |msg|
        # Use importance_score if available, otherwise use timestamp as proxy
        score = msg.importance_score || msg.timestamp.to_f
        -score  # Negative for descending order
      end

      # Add messages until we hit the token limit
      sorted_others.each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected << msg
          total += msg_tokens
        else
          # Stop when we can't fit any more messages
          break
        end
      end

      # Re-sort by timestamp to maintain conversation order
      selected.sort_by(&:timestamp)
    end
    
    # Logging helper methods
    def log_debug(message)
      return unless SmartPrompt.logger
      SmartPrompt.logger.debug "[HybridStrategy] #{message}"
    end
  end
end
