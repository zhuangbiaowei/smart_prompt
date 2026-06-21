require_relative 'context_strategy'

module SmartPrompt
  # SlidingWindowStrategy implements a simple context selection strategy
  # that keeps the most recent N messages (sliding window approach)
  # 
  # This strategy:
  # - Preserves system messages regardless of window size
  # - Keeps the most recent N non-system messages
  # - Trims messages to fit within token limits if specified
  # - Is efficient and predictable for simple conversation flows
  class SlidingWindowStrategy
    include ContextStrategy

    # Initialize the sliding window strategy
    # @param config [Hash] Configuration options
    # @option config [Integer] :window_size (10) Number of recent messages to keep
    # @option config [Boolean] :preserve_system (true) Whether to always keep system messages
    def initialize(config = {})
      @window_size = config[:window_size] || 10
      @preserve_system = config[:preserve_system] != false
    end

    # Select messages using sliding window approach
    # @param messages [Array<Message>] All messages in the session
    # @param max_tokens [Integer, nil] Maximum token limit for selected messages
    # @param current_message [Message, nil] Not used in this strategy
    # @return [Array<Message>] Selected messages
    def select_messages(messages, max_tokens, current_message = nil)
      return [] if messages.nil? || messages.empty?

      # Separate system and non-system messages
      system_messages = @preserve_system ? messages.select(&:system_message?) : []
      non_system_messages = messages.reject(&:system_message?)

      # Get the most recent messages within window size
      recent_messages = non_system_messages.last(@window_size)

      # Combine system messages (at the beginning) with recent messages
      selected = system_messages + recent_messages

      # Log selection decision
      log_debug "SlidingWindowStrategy: selected #{selected.count}/#{messages.count} messages (window_size=#{@window_size}, system=#{system_messages.count}, recent=#{recent_messages.count})"

      # Trim to token limit if specified
      result = max_tokens ? trim_to_token_limit(selected, max_tokens) : selected
      
      if max_tokens && result.count < selected.count
        tokens_before = selected.sum { |m| m.token_count || 0 }
        tokens_after = result.sum { |m| m.token_count || 0 }
        log_debug "SlidingWindowStrategy: trimmed to token limit #{max_tokens}: #{selected.count} -> #{result.count} messages, #{tokens_before} -> #{tokens_after} tokens"
      end
      
      result
    end

    # Determine if compression should be triggered
    # Recommends compression when message count exceeds 2x window size
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if message count > 2 * window_size
    def should_compress?(session)
      session.message_count > @window_size * 2
    end

    private

    # Trim messages to fit within token limit
    # Removes messages from the beginning (oldest first) until within limit
    # @param messages [Array<Message>] Messages to trim
    # @param max_tokens [Integer] Maximum token limit
    # @return [Array<Message>] Trimmed messages
    def trim_to_token_limit(messages, max_tokens)
      return messages unless max_tokens
      return [] if messages.empty?

      # Calculate tokens from newest to oldest, keeping messages that fit
      total = 0
      selected = []

      messages.reverse_each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected.unshift(msg)
          total += msg_tokens
        else
          # Stop adding messages once we exceed the limit
          break
        end
      end

      selected
    end
    
    # Logging helper methods
    def log_debug(message)
      return unless SmartPrompt.logger
      SmartPrompt.logger.debug "[SlidingWindowStrategy] #{message}"
    end
  end
end
