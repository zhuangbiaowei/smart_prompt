require 'minitest/autorun'
require_relative '../lib/smart_prompt'

class TokenCounterTest < Minitest::Test
  def setup
    @counter = SmartPrompt::TokenCounter.new
  end

  def test_count_simple_text
    text = "Hello, world!"
    count = @counter.count(text)
    assert count > 0, "Token count should be greater than 0"
  end

  def test_count_empty_text
    assert_equal 0, @counter.count("")
    assert_equal 0, @counter.count(nil)
  end

  def test_caching_works
    text = "This is a test message for caching"
    
    # First call should calculate
    count1 = @counter.count(text)
    
    # Second call should use cache
    count2 = @counter.count(text)
    
    assert_equal count1, count2, "Cached count should match original"
    assert_equal 1, @counter.cache_size, "Cache should contain one entry"
  end

  def test_count_messages
    messages = [
      SmartPrompt::Message.new(role: "user", content: "Hello"),
      SmartPrompt::Message.new(role: "assistant", content: "Hi there!")
    ]
    
    # Calculate tokens for each message first
    messages.each { |msg| msg.calculate_tokens(@counter) }
    
    total = @counter.count_messages(messages)
    assert total > 0, "Total token count should be greater than 0"
  end

  def test_clear_cache
    @counter.count("Test message")
    assert_equal 1, @counter.cache_size
    
    @counter.clear_cache
    assert_equal 0, @counter.cache_size
  end
end
