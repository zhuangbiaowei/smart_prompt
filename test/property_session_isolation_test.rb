require 'minitest/autorun'
require 'rantly'
require 'rantly/property'
require 'rantly/shrinks'
require './lib/smart_prompt'

# Property-based tests for Session Isolation
class PropertySessionIsolationTest < Minitest::Test
  # **Feature: history-optimization, Property 1: Session Isolation**
  # For any two distinct sessions and any message, adding the message to one session
  # should not cause it to appear in the other session's history.
  # **Validates: Requirements 1.1, 1.2, 1.3, 1.4**
  def test_property_session_isolation
    test_case = self
    
    Rantly(100) do
      # Generate two distinct session IDs
      session1_id = string(/[a-z0-9_]{5,20}/)
      session2_id = string(/[a-z0-9_]{5,20}/)
      guard session1_id != session2_id
      
      # Generate a random message
      message = {
        role: choose("user", "assistant", "system"),
        content: sized(range(10, 200)) { string }
      }
      
      # Persistence disabled: each manager must be fully in-memory isolated,
      # otherwise random session IDs collide across iterations/tests via ./history_data.
      manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
      
      # Add message to session1
      manager.add_message(session1_id, message)
      
      # Get messages from both sessions
      session1_messages = manager.get_context(session1_id)
      session2_messages = manager.get_context(session2_id)
      
      # Verify session1 has the message
      test_case.assert_equal 1, session1_messages.length, 
        "Session 1 should have exactly 1 message"
      test_case.assert_equal message[:content], session1_messages[0].content,
        "Session 1 should contain the added message"
      
      # Verify session2 does NOT have the message (isolation)
      test_case.assert_equal 0, session2_messages.length,
        "Session 2 should be empty - messages should not leak between sessions"
    end
  end
  
  # Additional property test: Multiple messages across multiple sessions
  # This tests that isolation holds even with many messages and sessions
  def test_property_session_isolation_multiple_messages
    test_case = self
    
    Rantly(100) do
      # Generate 2-5 distinct session IDs
      num_sessions = range(2, 5)
      session_ids = array(num_sessions) { string(/[a-z0-9_]{5,20}/) }.uniq
      guard session_ids.length >= 2  # Ensure we have at least 2 distinct sessions
      
      # Generate 1-10 messages per session
      messages_per_session = range(1, 10)
      
      # Persistence disabled: each manager must be fully in-memory isolated,
      # otherwise random session IDs collide across iterations/tests via ./history_data.
      manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
      
      # Track what messages we add to each session
      expected_counts = {}
      
      # Add messages to each session
      session_ids.each do |session_id|
        expected_counts[session_id] = messages_per_session
        
        messages_per_session.times do |i|
          manager.add_message(session_id, {
            role: "user",
            content: "Message #{i} for session #{session_id}"
          })
        end
      end
      
      # Verify each session has exactly the messages we added to it
      session_ids.each do |session_id|
        messages = manager.get_context(session_id)
        
        test_case.assert_equal expected_counts[session_id], messages.length,
          "Session #{session_id} should have exactly #{expected_counts[session_id]} messages"
        
        # Verify all messages belong to this session
        messages.each do |msg|
          test_case.assert msg.content.include?(session_id),
            "Message in session #{session_id} should contain the session ID"
        end
      end
    end
  end
  
  # Property test: Concurrent session operations maintain isolation
  # This tests thread safety and isolation under concurrent access
  def test_property_session_isolation_concurrent
    test_case = self
    
    Rantly(50) do
      # Generate distinct session IDs
      session1_id = string(/[a-z0-9_]{5,20}/)
      session2_id = string(/[a-z0-9_]{5,20}/)
      guard session1_id != session2_id
      
      # Number of messages to add concurrently
      num_messages = range(5, 20)
      
      # Persistence disabled: each manager must be fully in-memory isolated,
      # otherwise random session IDs collide across iterations/tests via ./history_data.
      manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
      
      # Create threads that add messages to different sessions concurrently
      threads = []
      
      threads << Thread.new do
        num_messages.times do |i|
          manager.add_message(session1_id, {
            role: "user",
            content: "Session1 message #{i}"
          })
        end
      end
      
      threads << Thread.new do
        num_messages.times do |i|
          manager.add_message(session2_id, {
            role: "user",
            content: "Session2 message #{i}"
          })
        end
      end
      
      # Wait for all threads to complete
      threads.each(&:join)
      
      # Verify isolation after concurrent operations
      session1_messages = manager.get_context(session1_id)
      session2_messages = manager.get_context(session2_id)
      
      test_case.assert_equal num_messages, session1_messages.length,
        "Session 1 should have exactly #{num_messages} messages"
      test_case.assert_equal num_messages, session2_messages.length,
        "Session 2 should have exactly #{num_messages} messages"
      
      # Verify no cross-contamination
      session1_messages.each do |msg|
        test_case.assert msg.content.include?("Session1"),
          "Session 1 should only contain Session1 messages"
        test_case.refute msg.content.include?("Session2"),
          "Session 1 should not contain Session2 messages"
      end
      
      session2_messages.each do |msg|
        test_case.assert msg.content.include?("Session2"),
          "Session 2 should only contain Session2 messages"
        test_case.refute msg.content.include?("Session1"),
          "Session 2 should not contain Session1 messages"
      end
    end
  end
end
