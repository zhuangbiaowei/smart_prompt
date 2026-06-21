require 'minitest/autorun'
require './lib/smart_prompt'
require 'yaml'
require 'fileutils'

# Integration test to verify Conversation class works with HistoryManager
class ConversationIntegrationTest < Minitest::Test
  def setup
    # Create a test configuration file
    @test_config_path = "./test_config_#{Process.pid}.yml"
    @test_storage_path = "./history_data_test_conversation_#{Process.pid}_#{Time.now.to_i}"
    @test_worker_path = "./test_workers_#{Process.pid}"
    @test_template_path = "./test_templates_#{Process.pid}"
    
    # Create necessary directories
    FileUtils.mkdir_p(@test_storage_path)
    FileUtils.mkdir_p(@test_worker_path)
    FileUtils.mkdir_p(@test_template_path)
    
    # Create test configuration
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

  def test_conversation_with_history_manager
    # Verify HistoryManager is initialized
    assert_instance_of SmartPrompt::HistoryManager, @engine.history_manager
    
    # Create a conversation with a session ID
    session_id = "test_session_#{Time.now.to_i}"
    conversation = SmartPrompt::Conversation.new(@engine, nil, session_id)
    
    # Add messages with history enabled
    conversation.add_message({ role: "system", content: "You are a helpful assistant." }, true)
    conversation.add_message({ role: "user", content: "Hello!" }, true)
    conversation.add_message({ role: "assistant", content: "Hi there!" }, true)
    
    # Verify messages are stored in HistoryManager
    context = @engine.history_manager.get_context(session_id)
    assert_equal 3, context.length
    
    # Verify history_messages returns correct format
    history = conversation.history_messages
    assert_equal 3, history.length
    assert_equal "system", history[0][:role]
    assert_equal "You are a helpful assistant.", history[0][:content]
  end

  def test_conversation_without_history_manager
    # Create engine without history configuration
    config_without_history = {
      'adapters' => { 'test' => 'OpenAIAdapter' },
      'llms' => { 'test_llm' => { 'adapter' => 'test', 'api_key' => 'test_key' } },
      'template_path' => @test_template_path,
      'worker_path' => @test_worker_path,
      'logger_file' => './logs/smart_prompt.log'
    }
    
    config_path = "./test_config_no_history_#{Process.pid}.yml"
    File.write(config_path, config_without_history.to_yaml)
    
    engine = SmartPrompt::Engine.new(config_path)
    
    # Verify HistoryManager is not initialized
    assert_nil engine.history_manager
    
    # Create conversation
    conversation = SmartPrompt::Conversation.new(engine)
    
    # Add messages with history - should fall back to old implementation
    conversation.add_message({ role: "user", content: "Test" }, true)
    
    # Verify it uses engine.history_messages
    assert_equal 1, engine.history_messages.length
    
    # Clean up
    File.delete(config_path) if File.exist?(config_path)
  end

  def test_backward_compatibility_with_history_parameter
    session_id = "compat_test_#{Time.now.to_i}"
    conversation = SmartPrompt::Conversation.new(@engine, nil, session_id)
    
    # Add message without history
    conversation.add_message({ role: "user", content: "No history" }, false)
    
    # Verify it's only in conversation messages, not in HistoryManager
    assert_equal 1, conversation.instance_variable_get(:@messages).length
    context = @engine.history_manager.get_context(session_id)
    assert_equal 0, context.length
    
    # Add message with history
    conversation.add_message({ role: "user", content: "With history" }, true)
    
    # Verify it's in both places
    assert_equal 2, conversation.instance_variable_get(:@messages).length
    context = @engine.history_manager.get_context(session_id)
    assert_equal 1, context.length
  end

  def test_default_session_creation
    # Create conversation without explicit session ID
    conversation = SmartPrompt::Conversation.new(@engine)
    
    # Add message with history - should create default session
    conversation.add_message({ role: "user", content: "Test" }, true)
    
    # Verify a session was created
    session_id = conversation.instance_variable_get(:@session_id)
    refute_nil session_id
    assert session_id.start_with?("default_")
    
    # Verify message is in the session
    context = @engine.history_manager.get_context(session_id)
    assert_equal 1, context.length
  end

  def test_session_isolation_in_conversations
    # Create two conversations with different session IDs
    session1_id = "session1_#{Time.now.to_i}"
    session2_id = "session2_#{Time.now.to_i}"
    
    conv1 = SmartPrompt::Conversation.new(@engine, nil, session1_id)
    conv2 = SmartPrompt::Conversation.new(@engine, nil, session2_id)
    
    # Add messages to each conversation
    conv1.add_message({ role: "user", content: "Message for session 1" }, true)
    conv2.add_message({ role: "user", content: "Message for session 2" }, true)
    
    # Verify isolation
    history1 = conv1.history_messages
    history2 = conv2.history_messages
    
    assert_equal 1, history1.length
    assert_equal 1, history2.length
    assert_equal "Message for session 1", history1[0][:content]
    assert_equal "Message for session 2", history2[0][:content]
  end

  def test_message_format_conversion
    session_id = "format_test_#{Time.now.to_i}"
    conversation = SmartPrompt::Conversation.new(@engine, nil, session_id)
    
    # Add a message with metadata
    message = {
      role: "user",
      content: "Test message",
      metadata: { importance: 0.9 }
    }
    conversation.add_message(message, true)
    
    # Get history and verify format
    history = conversation.history_messages
    assert_equal 1, history.length
    assert_equal "user", history[0][:role]
    assert_equal "Test message", history[0][:content]
    assert_instance_of Hash, history[0]
  end
end
