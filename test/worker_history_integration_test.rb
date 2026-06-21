require 'minitest/autorun'
require './lib/smart_prompt'
require 'yaml'
require 'fileutils'

# Integration test to verify Worker class works with HistoryManager
class WorkerHistoryIntegrationTest < Minitest::Test
  def setup
    # Create test directories
    @test_config_path = "./test_worker_config_#{Process.pid}.yml"
    @test_storage_path = "./history_data_test_worker_#{Process.pid}_#{Time.now.to_i}"
    @test_worker_path = "./test_workers_worker_#{Process.pid}"
    @test_template_path = "./test_templates_worker_#{Process.pid}"
    
    FileUtils.mkdir_p(@test_storage_path)
    FileUtils.mkdir_p(@test_worker_path)
    FileUtils.mkdir_p(@test_template_path)
    
    # Create test configuration with history enabled
    config = {
      'adapters' => {
        'test' => 'OpenAIAdapter'
      },
      'llms' => {
        'test_llm' => {
          'adapter' => 'test',
          'api_key' => 'test_key',
          'url' => 'http://test.com'
        }
      },
      'template_path' => @test_template_path,
      'worker_path' => @test_worker_path,
      'logger_file' => './logs/smart_prompt.log',
      'history' => {
        'cache_size' => 10,
        'session_defaults' => {
          'max_messages' => 50,
          'max_tokens' => 2000
        },
        'persistence' => {
          'enabled' => true,
          'storage_path' => @test_storage_path
        }
      }
    }
    
    File.write(@test_config_path, config.to_yaml)
    
    # Initialize engine
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Define test worker programmatically
    SmartPrompt::Worker.define(:test_history_worker) do
      @conversation.add_message({ role: "system", content: "Test system message" }, params[:with_history])
      @conversation.add_message({ role: "user", content: "Test user message" }, params[:with_history])
      "Worker executed"
    end
  end

  def teardown
    # Shutdown history manager
    @engine.history_manager.shutdown if @engine.history_manager
    
    # Clean up test files and directories
    File.delete(@test_config_path) if File.exist?(@test_config_path)
    FileUtils.rm_rf(@test_storage_path) if File.exist?(@test_storage_path)
    FileUtils.rm_rf(@test_worker_path) if File.exist?(@test_worker_path)
    FileUtils.rm_rf(@test_template_path) if File.exist?(@test_template_path)
  end

  def test_worker_with_default_session_creation
    # Test default session creation through Worker.execute
    worker = SmartPrompt::Worker.new(:test_history_worker, @engine)
    
    # Execute with history enabled but no session_id
    result = worker.execute(with_history: true)
    
    assert_equal "Worker executed", result
    
    # Verify a default session was created
    session_ids = @engine.history_manager.session_ids
    assert_equal 1, session_ids.length
    
    # Verify the session ID follows the pattern
    session_id = session_ids.first
    assert session_id.start_with?("worker_test_history_worker_")
    
    # Verify messages are in the session
    context = @engine.history_manager.get_context(session_id)
    assert_equal 2, context.length
    assert_equal "system", context[0].role
    assert_equal "Test system message", context[0].content
  end

  def test_worker_with_explicit_session_id
    # Call worker with explicit session_id
    custom_session_id = "custom_session_#{Time.now.to_i}"
    worker = SmartPrompt::Worker.new(:test_history_worker, @engine)
    result = worker.execute(with_history: true, session_id: custom_session_id)
    
    assert_equal "Worker executed", result
    
    # Verify the custom session was used
    assert @engine.history_manager.session_exists?(custom_session_id)
    
    # Verify messages are in the correct session
    context = @engine.history_manager.get_context(custom_session_id)
    assert_equal 2, context.length
  end

  def test_worker_without_history
    # Call worker without history
    worker = SmartPrompt::Worker.new(:test_history_worker, @engine)
    result = worker.execute(with_history: false)
    
    assert_equal "Worker executed", result
    
    # Verify no sessions were created
    session_ids = @engine.history_manager.session_ids
    assert_equal 0, session_ids.length
  end

  def test_multiple_worker_calls_same_session
    # Call worker multiple times with the same session
    session_id = "persistent_session_#{Time.now.to_i}"
    worker = SmartPrompt::Worker.new(:test_history_worker, @engine)
    
    3.times do
      worker.execute(with_history: true, session_id: session_id)
    end
    
    # Verify all messages are accumulated in the same session
    context = @engine.history_manager.get_context(session_id)
    # Each call adds 2 messages, so 3 calls = 6 messages
    assert_equal 6, context.length
  end

  def test_worker_session_isolation
    # Call worker with different sessions
    session1 = "session1_#{Time.now.to_i}"
    session2 = "session2_#{Time.now.to_i}"
    
    # Create separate worker instances to avoid conversation reuse
    worker1 = SmartPrompt::Worker.new(:test_history_worker, @engine)
    worker2 = SmartPrompt::Worker.new(:test_history_worker, @engine)
    
    worker1.execute(with_history: true, session_id: session1)
    worker2.execute(with_history: true, session_id: session2)
    
    # Verify isolation
    context1 = @engine.history_manager.get_context(session1)
    context2 = @engine.history_manager.get_context(session2)
    
    assert_equal 2, context1.length
    assert_equal 2, context2.length
    
    # Verify they are different sessions
    assert_equal 2, @engine.history_manager.session_ids.length
  end
end
