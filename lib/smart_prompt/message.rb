require 'time'

module SmartPrompt
  # Message represents a single message in a conversation history
  # It contains role, content, timestamp, and metadata
  class Message
    attr_reader :role, :content, :timestamp, :metadata, :token_count
    attr_accessor :importance_score, :is_summary

    def initialize(data)
      @role = data[:role] || data["role"]
      @content = data[:content] || data["content"]
      @timestamp = parse_timestamp(data[:timestamp] || data["timestamp"])
      @metadata = data[:metadata] || data["metadata"] || {}
      @token_count = nil  # Lazy calculation
      @importance_score = data[:importance_score] || data["importance_score"]
      @is_summary = data[:is_summary] || data["is_summary"] || false
    end

    # Calculate token count using provided counter
    def calculate_tokens(counter)
      @token_count ||= counter.count(@content)
    end

    # Check if this is a system message
    def system_message?
      @role == "system" || @role == :system
    end

    # Convert message to hash format
    def to_h
      {
        role: @role,
        content: @content,
        timestamp: @timestamp.iso8601,
        metadata: @metadata,
        importance_score: @importance_score,
        is_summary: @is_summary
      }
    end

    private

    def parse_timestamp(timestamp)
      case timestamp
      when Time
        timestamp
      when String
        Time.parse(timestamp)
      when nil
        Time.now
      else
        Time.now
      end
    end
  end
end
