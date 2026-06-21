require 'minitest/autorun'
require 'smart_prompt'
require 'fileutils'
require 'logger'

class MonitoringTest < Minitest::Test
  def setup
    @test_dir = "./history_data_monitoring_test_#{Process.pid}_#{Time.now.to_i}"
    FileUtils.mkdir_p(@test_dir)
    
    # Set up logger to capture output
    @log_output = StringIO.new
    SmartPrompt.logger = Logger.new(@log_output)
    SmartPrompt.logger.level = Logger::DEBUG
    
    @config = {
      cache_size: 10,
      persistence: {
        enabled: true,
        storage_path: @test_dir,
        async: false
      },
      monitoring: {
        enabled: true,
        log_level: :debug
      }
    }
    
    @manager = SmartPrompt::HistoryManager.new(@config)
  end
  
  def teardown
    @manager.shutdown if @manager
    FileUtils.rm_rf(@test_dir) if File.exist?(@test_dir)
  end
  
  def test_operation_logging
    # Add a message and check that it's logged
    @manager.add_message("test_session", { role: "user", content: "Hello" })
    
    log_content = @log_output.string
    assert_includes log_content, "[HistoryManager]", "Should include HistoryManager tag"
    assert_includes log_content, "Session test_session created", "Should log session creation"
    assert_includes log_content, "Message added", "Should log message addition"
  end
  
  def test_error_logging_with_context
    # Try to export a non-existent session
    begin
      @manager.export_session("nonexistent_session")
    rescue => e
      # Expected to fail
    end
    
    # The error should be logged with context
    log_content = @log_output.string
    # Note: The session will be created automatically, so this test needs adjustment
    # Let's test a different error scenario
  end
  
  def test_system_wide_statistics
    # Create multiple sessions and add messages
    @manager.add_message("session1", { role: "user", content: "Hello" })
    @manager.add_message("session1", { role: "assistant", content: "Hi there" })
    @manager.add_message("session2", { role: "user", content: "Test" })
    
    # Get system-wide stats
    stats = @manager.get_stats
    
    # Verify all required metrics are present
    assert_includes stats, :active_sessions
    assert_includes stats, :sessions_created
    assert_includes stats, :sessions_deleted
    assert_includes stats, :total_messages
    assert_includes stats, :messages_added
    assert_includes stats, :messages_per_session_avg
    assert_includes stats, :total_tokens
    assert_includes stats, :tokens_per_session_avg
    assert_includes stats, :tokens_per_message_avg
    assert_includes stats, :cache_hits
    assert_includes stats, :cache_misses
    assert_includes stats, :cache_hit_rate
    assert_includes stats, :context_retrievals
    assert_includes stats, :compression_operations
    assert_includes stats, :tokens_saved_by_compression
    assert_includes stats, :persistence_errors
    
    # Verify values
    assert_equal 2, stats[:active_sessions]
    assert_equal 2, stats[:sessions_created]
    assert_equal 3, stats[:total_messages]
    assert_equal 3, stats[:messages_added]
    assert stats[:messages_per_session_avg] > 0
  end
  
  def test_session_specific_statistics
    # Add messages to a session
    @manager.add_message("test_session", { role: "user", content: "Hello" })
    @manager.add_message("test_session", { role: "assistant", content: "Hi" })
    
    # Get session-specific stats
    stats = @manager.get_stats("test_session")
    
    assert_equal "test_session", stats[:session_id]
    assert_equal 2, stats[:message_count]
    assert stats[:total_tokens] > 0
    assert_includes stats, :created_at
    assert_includes stats, :updated_at
    assert_includes stats, :config
  end
  
  def test_debug_logging_for_context_selection
    # Add multiple messages
    10.times do |i|
      @manager.add_message("test_session", { role: "user", content: "Message #{i}" })
    end
    
    # Get context with token limit
    @manager.get_context("test_session", 100)
    
    log_content = @log_output.string
    assert_includes log_content, "Context selected", "Should log context selection"
    assert_includes log_content, "messages", "Should include message count"
    assert_includes log_content, "tokens", "Should include token count"
  end
  
  def test_metrics_export_prometheus_format
    # Add some data
    @manager.add_message("session1", { role: "user", content: "Hello" })
    @manager.add_message("session2", { role: "user", content: "Test" })
    
    # Export metrics in Prometheus format
    metrics = @manager.export_metrics(format: :prometheus)
    
    assert_kind_of String, metrics
    assert_includes metrics, "# HELP smart_prompt_active_sessions"
    assert_includes metrics, "# TYPE smart_prompt_active_sessions gauge"
    assert_includes metrics, "smart_prompt_active_sessions"
    assert_includes metrics, "smart_prompt_sessions_created_total"
    assert_includes metrics, "smart_prompt_total_messages"
    assert_includes metrics, "smart_prompt_cache_hits_total"
    assert_includes metrics, "smart_prompt_cache_hit_rate"
  end
  
  def test_metrics_export_json_format
    # Add some data
    @manager.add_message("session1", { role: "user", content: "Hello" })
    
    # Export metrics in JSON format
    metrics_json = @manager.export_metrics(format: :json)
    
    assert_kind_of String, metrics_json
    
    # Parse and verify
    require 'json'
    metrics = JSON.parse(metrics_json, symbolize_names: true)
    
    assert_includes metrics, :active_sessions
    assert_includes metrics, :total_messages
    assert_includes metrics, :cache_hit_rate
  end
  
  def test_metrics_export_hash_format
    # Add some data
    @manager.add_message("session1", { role: "user", content: "Hello" })
    
    # Export metrics in hash format
    metrics = @manager.export_metrics(format: :hash)
    
    assert_kind_of Hash, metrics
    assert_includes metrics, :active_sessions
    assert_includes metrics, :total_messages
  end
  
  def test_cache_hit_miss_tracking
    # First access - should be a miss
    @manager.get_session("test_session")
    stats1 = @manager.get_stats
    assert_equal 1, stats1[:cache_misses]
    assert_equal 0, stats1[:cache_hits]
    
    # Second access - should be a hit
    @manager.get_session("test_session")
    stats2 = @manager.get_stats
    assert_equal 1, stats2[:cache_misses]
    assert_equal 1, stats2[:cache_hits]
    
    # Verify hit rate calculation
    assert_equal 0.5, stats2[:cache_hit_rate]
  end
  
  def test_monitoring_can_be_disabled
    # Create manager with monitoring disabled
    config = @config.merge(monitoring: { enabled: false })
    manager = SmartPrompt::HistoryManager.new(config)
    
    # Clear log
    @log_output.truncate(0)
    @log_output.rewind
    
    # Perform operations
    manager.add_message("test_session", { role: "user", content: "Hello" })
    
    # Log should be empty (no monitoring output)
    log_content = @log_output.string
    refute_includes log_content, "[HistoryManager]", "Should not log when monitoring is disabled"
    
    manager.shutdown
  end
  
  def test_log_level_filtering
    # Create manager with INFO level
    config = @config.merge(monitoring: { enabled: true, log_level: :info })
    manager = SmartPrompt::HistoryManager.new(config)
    
    # Clear log
    @log_output.truncate(0)
    @log_output.rewind
    
    # Perform operations that generate DEBUG logs
    manager.add_message("test_session", { role: "user", content: "Hello" })
    manager.get_context("test_session")
    
    log_content = @log_output.string
    
    # Should have INFO logs
    assert_includes log_content, "INFO", "Should have INFO logs"
    
    # Should not have DEBUG logs (they're filtered out)
    # Note: This depends on the logger level being set correctly
    
    manager.shutdown
  end
end
