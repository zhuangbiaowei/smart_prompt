require 'minitest/autorun'
require './lib/smart_prompt'

class HistoryManagerTest < Minitest::Test
  def setup
    # Use a unique test directory to avoid interference from other tests
    @test_storage_path = "./history_data_test_#{Process.pid}_#{Time.now.to_i}"
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

  def test_initialization
    assert_instance_of SmartPrompt::HistoryManager, @manager
    assert_equal 0, @manager.session_ids.length
  end

  def test_create_session
    session = @manager.get_session("test_session")
    assert_instance_of SmartPrompt::Session, session
    assert_equal "test_session", session.id
  end

  def test_session_isolation
    # Add message to session1
    @manager.add_message("session1", { role: "user", content: "Hello from session1" })
    
    # Add message to session2
    @manager.add_message("session2", { role: "user", content: "Hello from session2" })
    
    # Verify isolation
    session1_messages = @manager.get_context("session1")
    session2_messages = @manager.get_context("session2")
    
    assert_equal 1, session1_messages.length
    assert_equal 1, session2_messages.length
    assert_equal "Hello from session1", session1_messages[0].content
    assert_equal "Hello from session2", session2_messages[0].content
  end

  def test_add_message
    @manager.add_message("test_session", { role: "user", content: "Test message" })
    
    messages = @manager.get_context("test_session")
    assert_equal 1, messages.length
    assert_equal "user", messages[0].role
    assert_equal "Test message", messages[0].content
  end

  def test_get_stats_for_session
    @manager.add_message("test_session", { role: "user", content: "Message 1" })
    @manager.add_message("test_session", { role: "assistant", content: "Response 1" })
    
    stats = @manager.get_stats("test_session")
    assert_equal "test_session", stats[:session_id]
    assert_equal 2, stats[:message_count]
  end

  def test_get_stats_global
    @manager.add_message("session1", { role: "user", content: "Message 1" })
    @manager.add_message("session2", { role: "user", content: "Message 2" })
    
    stats = @manager.get_stats
    assert_equal 2, stats[:active_sessions]
    assert_equal 2, stats[:total_messages]
  end

  def test_clear_session
    @manager.add_message("test_session", { role: "system", content: "System message" })
    @manager.add_message("test_session", { role: "user", content: "User message" })
    
    @manager.clear_session("test_session", keep_system_messages: true)
    
    messages = @manager.get_context("test_session")
    assert_equal 1, messages.length
    assert_equal "system", messages[0].role
  end

  def test_delete_session
    @manager.add_message("test_session", { role: "user", content: "Test" })
    assert @manager.session_exists?("test_session")
    
    @manager.delete_session("test_session")
    assert !@manager.session_exists?("test_session")
  end

  def test_export_session
    @manager.add_message("test_session", { role: "user", content: "Test message" })
    
    exported = @manager.export_session("test_session", format: :hash)
    assert_equal "test_session", exported[:id]
    assert_equal 1, exported[:messages].length
  end

  def test_search_messages
    @manager.add_message("test_session", { role: "user", content: "Hello world" })
    @manager.add_message("test_session", { role: "user", content: "Goodbye world" })
    @manager.add_message("test_session", { role: "user", content: "Test message" })
    
    results = @manager.search_messages("test_session", "world")
    assert_equal 2, results.length
  end

  def test_cleanup_expired_sessions
    # Create manager with short TTL for testing
    manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      },
      cleanup: {
        auto_cleanup: false,  # Manual cleanup for testing
        session_ttl: 1  # 1 second TTL
      }
    )
    
    # Add a message to create a session
    manager.add_message("test_session", { role: "user", content: "Test" })
    assert manager.session_exists?("test_session")
    
    # Wait for session to expire
    sleep(2)
    
    # Manually trigger cleanup
    expired = manager.cleanup_expired_sessions
    
    # Verify session was cleaned up
    assert_includes expired, "test_session"
    assert !manager.session_exists?("test_session")
    
    manager.shutdown
  end

  def test_cleanup_with_custom_callback
    cleanup_called = false
    custom_callback = lambda do |session, age|
      cleanup_called = true
      # Custom logic: cleanup if session has more than 2 messages
      session.message_count > 2
    end
    
    manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      },
      cleanup: {
        auto_cleanup: false,
        session_ttl: 86400,  # Long TTL, callback will decide
        cleanup_callback: custom_callback
      }
    )
    
    # Add 3 messages to trigger custom cleanup
    manager.add_message("test_session", { role: "user", content: "Message 1" })
    manager.add_message("test_session", { role: "user", content: "Message 2" })
    manager.add_message("test_session", { role: "user", content: "Message 3" })
    
    # Trigger cleanup
    expired = manager.cleanup_expired_sessions
    
    # Verify callback was called and session was cleaned up
    assert cleanup_called
    assert_includes expired, "test_session"
    assert !manager.session_exists?("test_session")
    
    manager.shutdown
  end

  def test_automatic_cleanup_thread
    # Create manager with auto cleanup enabled and very short interval
    manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      },
      cleanup: {
        auto_cleanup: true,
        cleanup_interval: 1,  # 1 second interval
        session_ttl: 1  # 1 second TTL
      }
    )
    
    # Add a message to create a session
    manager.add_message("test_session", { role: "user", content: "Test" })
    assert manager.session_exists?("test_session")
    
    # Wait for automatic cleanup to occur
    sleep(3)
    
    # Verify session was automatically cleaned up
    assert !manager.session_exists?("test_session")
    
    manager.shutdown
  end

  def test_cleanup_preserves_recent_sessions
    manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      },
      cleanup: {
        auto_cleanup: false,
        session_ttl: 1  # 1 second TTL (wide margin vs the 3s sleep below)
      }
    )
    
    # Add an old session
    manager.add_message("old_session", { role: "user", content: "Old" })
    
    # Wait for it to age
    sleep(3)
    
    # Add a new session
    manager.add_message("new_session", { role: "user", content: "New" })
    
    # Trigger cleanup
    expired = manager.cleanup_expired_sessions
    
    # Verify only old session was cleaned up
    assert_includes expired, "old_session"
    assert !manager.session_exists?("old_session")
    assert manager.session_exists?("new_session")
    
    manager.shutdown
  end

  def test_shutdown_stops_cleanup_thread
    manager = SmartPrompt::HistoryManager.new(
      persistence: {
        enabled: true,
        storage_path: @test_storage_path
      },
      cleanup: {
        auto_cleanup: true,
        cleanup_interval: 1
      }
    )
    
    # Get reference to cleanup thread
    cleanup_thread = manager.instance_variable_get(:@cleanup_thread)
    assert cleanup_thread.alive?
    
    # Shutdown manager
    manager.shutdown
    
    # Wait a bit for thread to stop
    sleep(0.5)
    
    # Verify thread is no longer alive
    assert !cleanup_thread.alive?
  end
end
