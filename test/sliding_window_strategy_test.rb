require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class SlidingWindowStrategyTest < Minitest::Test
    def setup
      @strategy = SlidingWindowStrategy.new(window_size: 5)
      @token_counter = TokenCounter.new
    end

    def test_select_messages_with_empty_array
      result = @strategy.select_messages([], nil)
      assert_equal [], result
    end

    def test_select_messages_within_window_size
      messages = create_messages(3)
      result = @strategy.select_messages(messages, nil)
      assert_equal 3, result.length
    end

    def test_select_messages_exceeds_window_size
      messages = create_messages(10)
      result = @strategy.select_messages(messages, nil)
      assert_equal 5, result.length
      # Should keep the most recent 5 messages
      assert_equal messages[-5..-1], result
    end

    def test_preserves_system_messages
      messages = []
      messages << create_message("system", "You are a helpful assistant")
      messages += create_messages(10, role: "user")
      
      result = @strategy.select_messages(messages, nil)
      
      # Should have system message + 5 most recent user messages
      assert_equal 6, result.length
      assert result.first.system_message?
    end

    def test_trim_to_token_limit
      messages = create_messages(5)
      # Assuming each message has ~10 tokens
      result = @strategy.select_messages(messages, 25)
      
      # Should only include messages that fit within token limit
      assert result.length <= 5
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 25
    end

    def test_should_compress_when_exceeds_threshold
      session = Session.new("test", {})
      
      # Add messages below threshold
      5.times { session.add_message(role: "user", content: "Hello") }
      refute @strategy.should_compress?(session)
      
      # Add messages above threshold (2 * window_size = 10)
      6.times { session.add_message(role: "user", content: "Hello") }
      assert @strategy.should_compress?(session)
    end

    def test_window_size_configuration
      strategy = SlidingWindowStrategy.new(window_size: 3)
      messages = create_messages(10)
      result = strategy.select_messages(messages, nil)
      assert_equal 3, result.length
    end

    def test_preserve_system_false
      strategy = SlidingWindowStrategy.new(window_size: 5, preserve_system: false)
      messages = []
      messages << create_message("system", "System message")
      messages += create_messages(10, role: "user")
      
      result = strategy.select_messages(messages, nil)
      
      # Should only have 5 messages, system message not preserved
      assert_equal 5, result.length
      refute result.any?(&:system_message?)
    end

    private

    def create_messages(count, role: "user")
      count.times.map do |i|
        create_message(role, "Message #{i}")
      end
    end

    def create_message(role, content)
      msg = Message.new(role: role, content: content)
      msg.calculate_tokens(@token_counter)
      msg
    end
  end
end
