require 'minitest/autorun'
require './lib/smart_prompt'

class MessageTest < Minitest::Test
  def test_initialization_with_hash
    data = {
      role: "user",
      content: "Hello world",
      metadata: { importance: 0.8 }
    }
    
    message = SmartPrompt::Message.new(data)
    
    assert_equal "user", message.role
    assert_equal "Hello world", message.content
    assert_instance_of Time, message.timestamp
    assert_equal 0.8, message.metadata[:importance]
  end

  def test_initialization_with_string_keys
    data = {
      "role" => "assistant",
      "content" => "Hi there"
    }
    
    message = SmartPrompt::Message.new(data)
    
    assert_equal "assistant", message.role
    assert_equal "Hi there", message.content
  end

  def test_system_message_detection
    system_msg = SmartPrompt::Message.new({ role: "system", content: "System" })
    user_msg = SmartPrompt::Message.new({ role: "user", content: "User" })
    
    assert system_msg.system_message?
    assert !user_msg.system_message?
  end

  def test_system_message_with_symbol
    system_msg = SmartPrompt::Message.new({ role: :system, content: "System" })
    assert system_msg.system_message?
  end

  def test_to_h_conversion
    data = {
      role: "user",
      content: "Test",
      metadata: { key: "value" }
    }
    
    message = SmartPrompt::Message.new(data)
    hash = message.to_h
    
    assert_equal "user", hash[:role]
    assert_equal "Test", hash[:content]
    assert_instance_of String, hash[:timestamp]
    assert_equal "value", hash[:metadata][:key]
  end

  def test_timestamp_parsing_from_string
    timestamp_str = "2024-01-01T12:00:00Z"
    message = SmartPrompt::Message.new({
      role: "user",
      content: "Test",
      timestamp: timestamp_str
    })
    
    assert_instance_of Time, message.timestamp
  end

  def test_timestamp_defaults_to_now
    message = SmartPrompt::Message.new({ role: "user", content: "Test" })
    
    assert_instance_of Time, message.timestamp
    assert_in_delta Time.now.to_i, message.timestamp.to_i, 2
  end

  def test_importance_score
    message = SmartPrompt::Message.new({
      role: "user",
      content: "Test",
      importance_score: 0.9
    })
    
    assert_equal 0.9, message.importance_score
  end

  def test_is_summary_flag
    summary_msg = SmartPrompt::Message.new({
      role: "system",
      content: "Summary",
      is_summary: true
    })
    
    regular_msg = SmartPrompt::Message.new({
      role: "user",
      content: "Regular"
    })
    
    assert summary_msg.is_summary
    assert !regular_msg.is_summary
  end
end
