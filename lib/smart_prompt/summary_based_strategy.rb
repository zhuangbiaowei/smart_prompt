require_relative 'context_strategy'

module SmartPrompt
  # SummaryBasedStrategy implements a context selection strategy that
  # automatically compresses older messages through summarization
  # 
  # This strategy:
  # - Monitors message count and triggers summarization at threshold
  # - Keeps recent messages uncompressed for context continuity
  # - Generates summaries of older messages to reduce token usage
  # - Falls back to truncation when summarization fails
  # - Maintains conversation coherence while reducing token costs
  class SummaryBasedStrategy
    include ContextStrategy

    # Initialize the summary-based strategy
    # @param config [Hash] Configuration options
    # @option config [Integer] :summary_threshold (20) Message count that triggers summarization
    # @option config [Integer] :keep_recent (5) Number of recent messages to keep uncompressed
    # @option config [CompressionEngine] :compression_engine Engine for generating summaries
    # @option config [Boolean] :preserve_system (true) Whether to always keep system messages
    def initialize(config = {})
      @summary_threshold = config[:summary_threshold] || 20
      @keep_recent = config[:keep_recent] || 5
      @compression_engine = config[:compression_engine]
      @preserve_system = config[:preserve_system] != false

      # Create a default compression engine if none provided
      @compression_engine ||= CompressionEngine.new(config[:compression] || {})
    end

    # Select messages using summary-based approach
    # Automatically summarizes older messages when threshold is exceeded
    # @param messages [Array<Message>] All messages in the session
    # @param max_tokens [Integer, nil] Maximum token limit for selected messages
    # @param current_message [Message, nil] Not used in this strategy
    # @return [Array<Message>] Selected messages with summaries
    def select_messages(messages, max_tokens, current_message = nil)
      return [] if messages.nil? || messages.empty?

      # If below threshold, return messages (filtering system messages if needed)
      if messages.count <= @summary_threshold
        filtered = @preserve_system ? messages : messages.reject(&:system_message?)
        return max_tokens ? trim_to_token_limit(filtered, max_tokens) : filtered
      end

      # Separate system messages, summaries, and regular messages
      system_messages = @preserve_system ? messages.select(&:system_message?) : []
      existing_summaries = messages.select { |msg| msg.is_summary }
      regular_messages = messages.reject { |msg| msg.system_message? || msg.is_summary }

      # Keep the most recent messages
      recent_messages = regular_messages.last(@keep_recent)

      # Get older messages that need summarization
      old_messages = regular_messages[0...-@keep_recent]

      # Generate summary if we have old messages and no existing summary
      if !old_messages.empty? && existing_summaries.empty?
        begin
          summary = @compression_engine.summarize(old_messages)
          if summary
            # Combine: system messages + summary + recent messages
            selected = system_messages + [summary] + recent_messages
          else
            # If summarization failed, fall back to keeping more recent messages
            SmartPrompt.logger.warn "Summarization failed, falling back to recent messages only"
            fallback_count = [@summary_threshold / 2, regular_messages.count].min
            selected = system_messages + regular_messages.last(fallback_count)
          end
        rescue => e
          SmartPrompt.logger.error "Error during summarization: #{e.message}, using fallback"
          # Fallback: keep system messages and recent messages
          selected = system_messages + recent_messages
        end
      else
        # Use existing summaries if available
        selected = system_messages + existing_summaries + recent_messages
      end

      # Trim to token limit if specified
      max_tokens ? trim_to_token_limit(selected, max_tokens) : selected
    end

    # Determine if compression should be triggered
    # Recommends compression when message count exceeds threshold
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if message count > summary_threshold
    def should_compress?(session)
      return false if session.nil?
      session.message_count > @summary_threshold
    end

    private

    # Trim messages to fit within token limit
    # Prioritizes keeping system messages and summaries
    # @param messages [Array<Message>] Messages to trim
    # @param max_tokens [Integer] Maximum token limit
    # @return [Array<Message>] Trimmed messages
    def trim_to_token_limit(messages, max_tokens)
      return messages unless max_tokens
      return [] if messages.empty?

      # Separate into priority groups
      system_messages = messages.select(&:system_message?)
      summaries = messages.select { |msg| msg.is_summary && !msg.system_message? }
      regular_messages = messages.reject { |msg| msg.system_message? || msg.is_summary }

      # Start with system messages (highest priority)
      selected = []
      total = 0

      system_messages.each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected << msg
          total += msg_tokens
        else
          # If we can't fit system messages, we have a problem
          SmartPrompt.logger.warn "Token limit too small to fit all system messages"
          break
        end
      end

      # Add summaries (second priority)
      summaries.each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected << msg
          total += msg_tokens
        else
          break
        end
      end

      # Add regular messages from newest to oldest (third priority)
      regular_messages.reverse_each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected << msg
          total += msg_tokens
        else
          break
        end
      end

      # Sort by timestamp to maintain conversation order
      selected.sort_by(&:timestamp)
    end
  end
end
