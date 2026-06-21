require 'minitest/autorun'
require './lib/smart_prompt'

# Tests for thread safety in HistoryManager
class ThreadSafetyTest < Minitest::Test
  def test_concurrent_session_creation
    # Use larger limits to avoid message eviction during test
    manager = SmartPrompt::HistoryManager.new(
      session_defaults: { max_messages: 500, max_tokens: 100000 },
      persistence: { enabled: false }
    )
    
    # Create multiple threads that try to create/access sessions concurrently
    threads = []
    10.times do |i|
      threads << Thread.new do
        100.times do |j|
          session_id = "session_#{i % 5}"  # 5 different sessions
          manager.add_message(session_id, {
            role: "user",
            content: "Thread #{i}, Message #{j}"
          })
        end
      end
    end
    
    # Wait for all threads to complete
    threads.each(&:join)
    
    # Verify data integrity
    stats = manager.get_stats
    assert_equal 5, stats[:active_sessions]
    assert_equal 1000, stats[:total_messages]
  end
  
  def test_concurrent_read_write
    # Use larger limits to avoid message eviction during test
    manager = SmartPrompt::HistoryManager.new(
      session_defaults: { max_messages: 200, max_tokens: 100000 },
      persistence: { enabled: false }
    )
    session_id = "test_session"
    
    # Pre-populate with some messages
    10.times do |i|
      manager.add_message(session_id, {
        role: "user",
        content: "Initial message #{i}"
      })
    end
    
    # Create threads that read and write concurrently
    threads = []
    errors = []
    
    # Writer threads
    5.times do |i|
      threads << Thread.new do
        begin
          20.times do |j|
            manager.add_message(session_id, {
              role: "user",
              content: "Writer #{i}, Message #{j}"
            })
          end
        rescue => e
          errors << e
        end
      end
    end
    
    # Reader threads
    5.times do |i|
      threads << Thread.new do
        begin
          20.times do
            messages = manager.get_context(session_id)
            # Verify we get a consistent snapshot
            assert messages.is_a?(Array)
            assert messages.all? { |m| m.is_a?(SmartPrompt::Message) }
          end
        rescue => e
          errors << e
        end
      end
    end
    
    # Wait for all threads
    threads.each(&:join)
    
    # No errors should have occurred
    assert_empty errors, "Errors occurred during concurrent access: #{errors.inspect}"
    
    # Verify final state
    messages = manager.get_context(session_id)
    assert_equal 110, messages.length  # 10 initial + 100 from writers
  end
  
  def test_concurrent_lru_eviction
    manager = SmartPrompt::HistoryManager.new(cache_size: 10, persistence: { enabled: false })
    
    # Create threads that create many sessions concurrently
    threads = []
    20.times do |i|
      threads << Thread.new do
        10.times do |j|
          session_id = "thread_#{i}_session_#{j}"
          manager.add_message(session_id, {
            role: "user",
            content: "Message from thread #{i}"
          })
        end
      end
    end
    
    threads.each(&:join)
    
    # Cache should be at or below limit
    stats = manager.get_stats
    assert stats[:active_sessions] <= 10, 
      "Cache size should be enforced: #{stats[:active_sessions]} sessions"
  end
  
  def test_concurrent_delete_and_access
    manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
    
    # Pre-create sessions
    10.times do |i|
      manager.add_message("session_#{i}", {
        role: "user",
        content: "Initial message"
      })
    end
    
    threads = []
    errors = []
    
    # Threads that delete sessions
    5.times do |i|
      threads << Thread.new do
        begin
          manager.delete_session("session_#{i}")
        rescue => e
          errors << e
        end
      end
    end
    
    # Threads that try to access sessions
    10.times do |i|
      threads << Thread.new do
        begin
          # This might access a deleted session, which should create a new one
          manager.get_context("session_#{i}")
        rescue => e
          errors << e
        end
      end
    end
    
    threads.each(&:join)
    
    # No errors should occur
    assert_empty errors, "Errors during concurrent delete/access: #{errors.inspect}"
  end
  
  def test_concurrent_stats_collection
    manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
    
    threads = []
    stats_results = []
    
    # Writer threads
    5.times do |i|
      threads << Thread.new do
        10.times do |j|
          manager.add_message("session_#{i}", {
            role: "user",
            content: "Message #{j}"
          })
        end
      end
    end
    
    # Stats reader threads
    10.times do
      threads << Thread.new do
        5.times do
          stats = manager.get_stats
          stats_results << stats
        end
      end
    end
    
    threads.each(&:join)
    
    # All stats calls should have succeeded
    assert_equal 50, stats_results.length
    
    # Final stats should be consistent
    final_stats = manager.get_stats
    assert_equal 5, final_stats[:active_sessions]
    assert_equal 50, final_stats[:total_messages]
  end
  
  def test_no_race_condition_in_session_creation
    manager = SmartPrompt::HistoryManager.new(persistence: { enabled: false })
    session_id = "shared_session"
    
    # Multiple threads try to create the same session simultaneously
    threads = []
    created_sessions = []
    
    10.times do
      threads << Thread.new do
        session = manager.get_session(session_id)
        created_sessions << session.object_id
      end
    end
    
    threads.each(&:join)
    
    # All threads should have gotten the same session object
    assert_equal 1, created_sessions.uniq.length,
      "Multiple session objects created for same session_id"
  end
end
