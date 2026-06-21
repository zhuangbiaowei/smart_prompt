module SmartPrompt
  # ContextStrategy defines the interface for context selection strategies
  # Different strategies implement different algorithms for selecting which
  # messages to include in the context window based on various criteria
  module ContextStrategy
    # Select messages from the session to include in context
    # @param messages [Array<Message>] All messages in the session
    # @param max_tokens [Integer, nil] Maximum token limit for selected messages
    # @param current_message [Message, nil] The current message being processed (for relevance)
    # @return [Array<Message>] Selected messages that fit within constraints
    def select_messages(messages, max_tokens, current_message = nil)
      raise NotImplementedError, "#{self.class} must implement #select_messages"
    end

    # Determine if the session should be compressed
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if compression is recommended
    def should_compress?(session)
      raise NotImplementedError, "#{self.class} must implement #should_compress?"
    end
  end
end
