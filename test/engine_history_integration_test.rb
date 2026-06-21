require 'minitest/autorun'
require './lib/smart_prompt'
require 'yaml'
require 'fileutils'
require 'stringio'

# Integration test to verify Engine class properly integrates with HistoryManager
class EngineHistoryIntegrationTest < Minitest::Test
  def setup
    # Create test directories
    @test_config_path = "./test_engine_config_#{Process.pid}.yml"
    @test_storage_path = "./history_data_test_engine_#{Process.pid}_#{Time.now.to_i}"
    @test_worker_path = "./test_workers_engine_#{Process.pid}"
    @test_template_path = "./test_templates_engine_#{Process.pid}"
    
    FileUtils.mkdir_p(@test_storage_path)
    FileUtils.mkdir_p(@test_worker_path)
    FileUtils.mkdir_p(@test_template_path)
  end

  def teardown
    # Shutdown history manager if it exists
    @engine.history_manager.shutdown if @engine && @engine.history_manager
    
    # Clean up test files and directories
    File.delete(@test_config_path) if File.exist?(@test_config_path)
    FileUtils.rm_rf(@test_storage_path) if File.exist?(@test_storage_path)
    FileUtils.rm_rf(@test_worker_path) if File.exist?(@test_worker_path)
    FileUtils.rm_rf(@test_template_path) if File.exist?(@test_template_path)
  end

  def test_engine_initializes_history_manager_from_config
    # Create configuration with history section
    config = create_test_config(with_history: true)
    File.write(@test_config_path, config.to_yaml)
    
    # Initialize engine
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Verify HistoryManager was initialized
    refute_nil @engine.history_manager
    assert_instance_of SmartPrompt::HistoryManager, @engine.history_manager
  end

  def test_engine_without_history_config_has_no_history_manager
    # Create configuration without history section
    config = create_test_config(with_history: false)
    File.write(@test_config_path, config.to_yaml)
    
    # Initialize engine
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Verify HistoryManager was not initialized
    assert_nil @engine.history_manager
  end

  def test_history_manager_accessor_is_exposed
    config = create_test_config(with_history: true)
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Verify accessor works
    assert_respond_to @engine, :history_manager
    refute_nil @engine.history_manager
  end

  def test_history_manager_uses_config_from_yaml
    # Create configuration with specific history settings
    config = create_test_config(with_history: true)
    config['history']['cache_size'] = 25
    config['history']['session_defaults']['max_messages'] = 75
    config['history']['session_defaults']['max_tokens'] = 2000
    config['history']['session_defaults']['context_strategy'] = 'sliding_window'
    config['history']['session_defaults']['preserve_system_messages'] = true
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Verify configuration was passed to HistoryManager
    refute_nil @engine.history_manager
    
    # Create a session and verify it uses the configured defaults
    session_id = "test_session"
    session = @engine.history_manager.get_session(session_id)
    
    assert_equal 75, session.config[:max_messages]
  end

  def test_deprecated_history_messages_shows_warning_when_history_manager_present
    config = create_test_config(with_history: true)
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Capture log output
    log_output = StringIO.new
    original_logger = SmartPrompt.logger
    SmartPrompt.logger = Logger.new(log_output)
    
    # Call deprecated method
    result = @engine.history_messages
    
    # Verify warning was logged
    log_output.rewind
    log_content = log_output.read
    assert log_content.include?("DEPRECATED")
    assert log_content.include?("history_messages")
    assert log_content.include?("history_manager.get_context")
    
    # Verify method still works
    assert_instance_of Array, result
    
    # Restore logger
    SmartPrompt.logger = original_logger
  end

  def test_deprecated_clear_history_messages_shows_warning_when_history_manager_present
    config = create_test_config(with_history: true)
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Capture log output
    log_output = StringIO.new
    original_logger = SmartPrompt.logger
    SmartPrompt.logger = Logger.new(log_output)
    
    # Call deprecated method
    @engine.clear_history_messages
    
    # Verify warning was logged
    log_output.rewind
    log_content = log_output.read
    assert log_content.include?("DEPRECATED")
    assert log_content.include?("clear_history_messages")
    assert log_content.include?("history_manager.clear_session")
    
    # Restore logger
    SmartPrompt.logger = original_logger
  end

  def test_deprecated_methods_work_without_warning_when_no_history_manager
    config = create_test_config(with_history: false)
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Capture log output
    log_output = StringIO.new
    original_logger = SmartPrompt.logger
    SmartPrompt.logger = Logger.new(log_output)
    
    # Call methods
    @engine.history_messages
    @engine.clear_history_messages
    
    # Verify no deprecation warning was logged
    log_output.rewind
    log_content = log_output.read
    refute log_content.include?("DEPRECATED")
    
    # Restore logger
    SmartPrompt.logger = original_logger
  end

  def test_history_manager_persistence_path_from_config
    config = create_test_config(with_history: true)
    File.write(@test_config_path, config.to_yaml)
    
    @engine = SmartPrompt::Engine.new(@test_config_path)
    
    # Add a message to a session
    session_id = "persistent_test"
    session = @engine.history_manager.add_message(session_id, { role: "user", content: "Test" })
    
    # Force synchronous save to ensure file is written
    @engine.history_manager.instance_variable_get(:@persistence).save(session)
    
    # Verify file was created in the configured path
    expected_file = File.join(@test_storage_path, "#{session_id}.json")
    
    assert File.exist?(expected_file), "Session file should be created at configured path"
  end

  private

  def create_test_config(with_history: true)
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
      'logger_file' => './logs/smart_prompt.log'
    }
    
    if with_history
      config['history'] = {
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
    end
    
    config
  end
end
