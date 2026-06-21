require 'time'

module SmartPrompt
  # Session represents an isolated conversation session with its own message history
  class Session
    attr_reader :id, :messages, :metadata, :created_at, :updated_at, :config

    def initialize(id, config = {})
      @id = id
      @messages = []
      @metadata = {}
      @config = config
      @token_cache = {}
      @importance_scores = {}
      @created_at = Time.now
      @updated_at = Time.now
      @token_counter = TokenCounter.new
    end

    # Add a message to the session
    def add_message(message_data)
      message = message_data.is_a?(Message) ? message_data : Message.new(message_data)
      
      # Calculate token count for the message
      message.calculate_tokens(@token_counter)
      
      @messages << message
      @updated_at = Time.now
      enforce_limits
      message
    end

    # Get messages from the session
    def get_messages(count = nil)
      count ? @messages.last(count) : @messages
    end

    # Calculate total token count for all messages
    def total_tokens
      @messages.sum { |msg| msg.token_count || 0 }
    end

    # Get the number of messages in the session
    def message_count
      @messages.length
    end

    # Clear all messages except system messages if preserve_system is true
    def clear(preserve_system: true)
      if preserve_system
        @messages = @messages.select(&:system_message?)
      else
        @messages = []
      end
      @updated_at = Time.now
    end

    # Get importance score for a message at given index
    def get_importance_score(message_index)
      @importance_scores[message_index] ||= calculate_importance(message_index)
    end

    # Convert session to hash format for serialization
    def to_h
      {
        id: @id,
        messages: @messages.map(&:to_h),
        metadata: @metadata,
        created_at: @created_at.iso8601,
        updated_at: @updated_at.iso8601,
        config: @config
      }
    end

    private

    # Enforce message count and token limits
    def enforce_limits
      max_messages = @config[:max_messages]
      max_tokens = @config[:max_tokens]

      # Enforce message count limit
      if max_messages && @messages.length > max_messages
        remove_oldest_messages_to_limit(max_messages)
      end

      # Enforce token limit
      if max_tokens && total_tokens > max_tokens
        remove_oldest_messages_to_token_limit(max_tokens)
      end
    end

    # Remove oldest non-system messages to meet message count limit
    def remove_oldest_messages_to_limit(max_messages)
      system_messages = @messages.select(&:system_message?)
      non_system_messages = @messages.reject(&:system_message?)

      # Keep only the most recent non-system messages
      messages_to_keep = max_messages - system_messages.length
      messages_to_keep = [messages_to_keep, 0].max

      kept_non_system = non_system_messages.last(messages_to_keep)
      @messages = system_messages + kept_non_system
    end

    # Remove oldest non-system messages to meet token limit
    def remove_oldest_messages_to_token_limit(max_tokens)
      system_messages = @messages.select(&:system_message?)
      non_system_messages = @messages.reject(&:system_message?)

      system_tokens = system_messages.sum { |msg| msg.token_count || 0 }
      available_tokens = max_tokens - system_tokens

      # Keep adding messages from the end until we hit the token limit
      kept_messages = []
      current_tokens = 0

      non_system_messages.reverse_each do |msg|
        msg_tokens = msg.token_count || 0
        if current_tokens + msg_tokens <= available_tokens
          kept_messages.unshift(msg)
          current_tokens += msg_tokens
        else
          break
        end
      end

      @messages = system_messages + kept_messages
    end

    # Calculate importance score for a message
    # This is a simple implementation based on recency
    def calculate_importance(message_index)
      return 0.0 if @messages.empty?
      
      # Simple recency-based scoring: newer messages have higher scores
      message_index.to_f / @messages.length
    end
  end
end
