require 'minitest/autorun'
require_relative '../lib/smart_prompt'

class TokenIntegrationTest < Minitest::Test
  def setup
    @counter = SmartPrompt::TokenCounter.new
  end

  def test_message_token_calculation
    message = SmartPrompt::Message.new(
      role: "user",
      content: "This is a test message with some content"
    )
    
    # Token count should be nil before calculation
    assert_nil message.token_count
    
    # Calculate tokens
    message.calculate_tokens(@counter)
    
    # Token count should now be set
    refute_nil message.token_count
    assert message.token_count > 0
  end

  def test_message_token_caching
    message = SmartPrompt::Message.new(
      role: "user",
      content: "Test message for caching"
    )
    
    # Calculate tokens twice
    count1 = message.calculate_tokens(@counter)
    count2 = message.calculate_tokens(@counter)
    
    # Should return the same cached value
    assert_equal count1, count2
    assert_equal count1, message.token_count
  end

  def test_multiple_messages_with_counter
    messages = [
      SmartPrompt::Message.new(role: "system", content: "You are a helpful assistant"),
      SmartPrompt::Message.new(role: "user", content: "Hello"),
      SmartPrompt::Message.new(role: "assistant", content: "Hi there! How can I help?")
    ]
    
    # Calculate tokens for all messages
    messages.each { |msg| msg.calculate_tokens(@counter) }
    
    # All should have token counts
    messages.each do |msg|
      refute_nil msg.token_count
      assert msg.token_count > 0
    end
    
    # Counter should have cached all three
    assert_equal 3, @counter.cache_size
  end
end
