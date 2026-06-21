require 'minitest/autorun'
require './lib/smart_prompt'

# Integration test to verify core data structures work together
class CoreIntegrationTest < Minitest::Test
  def setup
    # Use a unique test directory to avoid interference from other tests
    @test_storage_path = "./history_data_test_integration_#{Process.pid}_#{Time.now.to_i}"
    @manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      }
    )
  end

  def teardown
    # Clean up test sessions
    @manager.session_ids.each do |session_id|
      @manager.delete_session(session_id)
    end
    @manager.shutdown
    
    # Remove test directory
    FileUtils.rm_rf(@test_storage_path) if File.exist?(@test_storage_path)
  end

  def test_complete_workflow
    # Create a session
    session_id = "integration_test_session"
    session = @manager.get_session(session_id, {
      max_messages: 10,
      max_tokens: 1000
    })
    
    assert_instance_of SmartPrompt::Session, session
    assert_equal session_id, session.id
    
    # Add messages
    @manager.add_message(session_id, {
      role: "system",
      content: "You are a helpful assistant."
    })
    
    @manager.add_message(session_id, {
      role: "user",
      content: "Hello, how are you?"
    })
    
    @manager.add_message(session_id, {
      role: "assistant",
      content: "I'm doing well, thank you!"
    })
    
    # Get context
    context = @manager.get_context(session_id)
    assert_equal 3, context.length
    
    # Verify message types
    assert_instance_of SmartPrompt::Message, context[0]
    assert context[0].system_message?
    
    # Get stats
    stats = @manager.get_stats(session_id)
    assert_equal 3, stats[:message_count]
    
    # Search messages
    results = @manager.search_messages(session_id, "helpful")
    assert_equal 1, results.length
    
    # Export session
    exported = @manager.export_session(session_id, format: :hash)
    assert_equal session_id, exported[:id]
    assert_equal 3, exported[:messages].length
    
    # Clear session
    @manager.clear_session(session_id, keep_system_messages: true)
    context = @manager.get_context(session_id)
    assert_equal 1, context.length
    assert context[0].system_message?
    
    # Delete session
    @manager.delete_session(session_id)
    assert !@manager.session_exists?(session_id)
  end

  def test_message_class_features
    message = SmartPrompt::Message.new({
      role: "user",
      content: "Test message",
      metadata: { importance: 0.8 }
    })
    
    assert_equal "user", message.role
    assert_equal "Test message", message.content
    assert_instance_of Time, message.timestamp
    assert_equal 0.8, message.metadata[:importance]
    assert !message.system_message?
    
    # Test to_h conversion
    hash = message.to_h
    assert_equal "user", hash[:role]
    assert_equal "Test message", hash[:content]
  end

  def test_session_class_features
    session = SmartPrompt::Session.new("test_session", {
      max_messages: 5
    })
    
    # Add messages
    5.times do |i|
      session.add_message({
        role: "user",
        content: "Message #{i}"
      })
    end
    
    assert_equal 5, session.message_count
    
    # Add one more - should trigger limit enforcement
    session.add_message({
      role: "user",
      content: "Message 5"
    })
    
    assert_equal 5, session.message_count
    assert_equal "Message 1", session.messages[0].content
  end

  def test_history_manager_features
    # Test multiple sessions
    @manager.add_message("session1", { role: "user", content: "Session 1 message" })
    @manager.add_message("session2", { role: "user", content: "Session 2 message" })
    @manager.add_message("session3", { role: "user", content: "Session 3 message" })
    
    # Verify isolation
    assert_equal 1, @manager.get_context("session1").length
    assert_equal 1, @manager.get_context("session2").length
    assert_equal 1, @manager.get_context("session3").length
    
    # Global stats
    stats = @manager.get_stats
    assert_equal 3, stats[:active_sessions]
    assert_equal 3, stats[:total_messages]
  end
end
