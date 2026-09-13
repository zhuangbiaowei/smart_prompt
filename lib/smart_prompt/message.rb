require 'time'

module SmartPrompt
  # Message represents a single message in a conversation history
  # It contains role, content, timestamp, and metadata
  class Message
    attr_reader :role, :content, :timestamp, :metadata, :token_count,
                :tool_calls, :tool_call_id, :reasoning_content
    attr_accessor :importance_score, :is_summary

    def initialize(data)
      @role = data[:role] || data["role"]
      @content = data[:content] || data["content"]
      @timestamp = parse_timestamp(data[:timestamp] || data["timestamp"])
      @metadata = data[:metadata] || data["metadata"] || {}
      @token_count = nil  # Lazy calculation
      @importance_score = data[:importance_score] || data["importance_score"]
      @is_summary = data[:is_summary] || data["is_summary"] || false
      # Tool-call pairing and reasoning fields must survive serialization so
      # HistoryManager round-trips don't drop tool_calls / tool_call_id /
      # reasoning_content and produce malformed tool requests.
      @tool_calls = data[:tool_calls] || data["tool_calls"]
      @tool_call_id = data[:tool_call_id] || data["tool_call_id"]
      @reasoning_content = data[:reasoning_content] || data["reasoning_content"]
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
      h = {
        role: @role,
        content: @content,
        timestamp: @timestamp.iso8601,
        metadata: @metadata,
        importance_score: @importance_score,
        is_summary: @is_summary
      }
      h[:tool_calls] = @tool_calls if @tool_calls
      h[:tool_call_id] = @tool_call_id if @tool_call_id
      h[:reasoning_content] = @reasoning_content if @reasoning_content
      h
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
