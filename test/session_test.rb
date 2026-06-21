require 'minitest/autorun'
require './lib/smart_prompt'

class SessionTest < Minitest::Test
  def setup
    @session = SmartPrompt::Session.new("test_session")
  end

  def test_initialization
    assert_equal "test_session", @session.id
    assert_equal 0, @session.message_count
    assert_instance_of Time, @session.created_at
  end

  def test_add_message
    @session.add_message({ role: "user", content: "Hello" })
    
    assert_equal 1, @session.message_count
    assert_equal "Hello", @session.messages[0].content
  end

  def test_add_message_updates_timestamp
    original_time = @session.updated_at
    sleep 0.01
    @session.add_message({ role: "user", content: "Test" })
    
    assert @session.updated_at > original_time
  end

  def test_get_messages_all
    @session.add_message({ role: "user", content: "Message 1" })
    @session.add_message({ role: "user", content: "Message 2" })
    
    messages = @session.get_messages
    assert_equal 2, messages.length
  end

  def test_get_messages_with_count
    @session.add_message({ role: "user", content: "Message 1" })
    @session.add_message({ role: "user", content: "Message 2" })
    @session.add_message({ role: "user", content: "Message 3" })
    
    messages = @session.get_messages(2)
    assert_equal 2, messages.length
    assert_equal "Message 2", messages[0].content
    assert_equal "Message 3", messages[1].content
  end

  def test_clear_preserves_system_messages
    @session.add_message({ role: "system", content: "System" })
    @session.add_message({ role: "user", content: "User" })
    @session.add_message({ role: "assistant", content: "Assistant" })
    
    @session.clear(preserve_system: true)
    
    assert_equal 1, @session.message_count
    assert_equal "system", @session.messages[0].role
  end

  def test_clear_removes_all_messages
    @session.add_message({ role: "system", content: "System" })
    @session.add_message({ role: "user", content: "User" })
    
    @session.clear(preserve_system: false)
    
    assert_equal 0, @session.message_count
  end

  def test_to_h_conversion
    @session.add_message({ role: "user", content: "Test" })
    
    hash = @session.to_h
    
    assert_equal "test_session", hash[:id]
    assert_equal 1, hash[:messages].length
    assert_instance_of String, hash[:created_at]
  end

  def test_message_count_limit
    session = SmartPrompt::Session.new("test", { max_messages: 3 })
    
    session.add_message({ role: "user", content: "Message 1" })
    session.add_message({ role: "user", content: "Message 2" })
    session.add_message({ role: "user", content: "Message 3" })
    session.add_message({ role: "user", content: "Message 4" })
    
    assert_equal 3, session.message_count
    assert_equal "Message 2", session.messages[0].content
  end

  def test_message_count_limit_preserves_system_messages
    session = SmartPrompt::Session.new("test", { max_messages: 3 })
    
    session.add_message({ role: "system", content: "System" })
    session.add_message({ role: "user", content: "Message 1" })
    session.add_message({ role: "user", content: "Message 2" })
    session.add_message({ role: "user", content: "Message 3" })
    
    assert_equal 3, session.message_count
    assert_equal "system", session.messages[0].role
    assert_equal "Message 2", session.messages[1].content
  end

  def test_token_counting_on_add_message
    session = SmartPrompt::Session.new("test")
    
    message = session.add_message({ role: "user", content: "Hello world" })
    
    refute_nil message.token_count
    assert message.token_count > 0
  end

  def test_total_tokens_calculation
    session = SmartPrompt::Session.new("test")
    
    session.add_message({ role: "user", content: "Hello" })
    session.add_message({ role: "user", content: "World" })
    
    total = session.total_tokens
    assert total > 0
    assert_equal session.messages.sum { |m| m.token_count }, total
  end

  def test_token_limit_enforcement
    # Create a session with a small token limit
    session = SmartPrompt::Session.new("test", { max_tokens: 50 })
    
    # Add messages that will exceed the limit
    session.add_message({ role: "user", content: "This is a short message" })
    session.add_message({ role: "user", content: "This is another short message" })
    session.add_message({ role: "user", content: "This is yet another message that should push us over the limit" })
    session.add_message({ role: "user", content: "And one more message" })
    
    # Verify token limit is enforced
    assert session.total_tokens <= 50, "Total tokens #{session.total_tokens} exceeds limit of 50"
  end

  def test_token_limit_preserves_system_messages
    session = SmartPrompt::Session.new("test", { max_tokens: 30 })
    
    session.add_message({ role: "system", content: "You are a helpful assistant" })
    session.add_message({ role: "user", content: "Hello there" })
    session.add_message({ role: "user", content: "How are you doing today?" })
    session.add_message({ role: "user", content: "Tell me something interesting" })
    
    # System message should always be preserved
    system_messages = session.messages.select(&:system_message?)
    assert_equal 1, system_messages.length
    assert_equal "system", session.messages[0].role
    
    # Total tokens should not exceed limit
    assert session.total_tokens <= 30, "Total tokens #{session.total_tokens} exceeds limit of 30"
  end

  def test_both_limits_enforced_together
    session = SmartPrompt::Session.new("test", { max_messages: 5, max_tokens: 40 })
    
    session.add_message({ role: "system", content: "System message" })
    session.add_message({ role: "user", content: "Message 1" })
    session.add_message({ role: "user", content: "Message 2" })
    session.add_message({ role: "user", content: "Message 3" })
    session.add_message({ role: "user", content: "Message 4" })
    session.add_message({ role: "user", content: "Message 5" })
    session.add_message({ role: "user", content: "Message 6" })
    
    # Both limits should be enforced
    assert session.message_count <= 5, "Message count #{session.message_count} exceeds limit of 5"
    assert session.total_tokens <= 40, "Total tokens #{session.total_tokens} exceeds limit of 40"
    
    # System message should be preserved
    assert_equal "system", session.messages[0].role
  end

  def test_no_limits_when_not_configured
    session = SmartPrompt::Session.new("test")
    
    # Add many messages
    20.times do |i|
      session.add_message({ role: "user", content: "Message #{i}" })
    end
    
    # All messages should be kept
    assert_equal 20, session.message_count
  end
end
