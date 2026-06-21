require 'minitest/autorun'
require 'fileutils'
require './lib/smart_prompt'

class PersistenceLayerTest < Minitest::Test
  def setup
    @test_storage_path = "./test_history_data"
    
    # Clean up any existing test data BEFORE creating persistence layer
    FileUtils.rm_rf(@test_storage_path) if Dir.exist?(@test_storage_path)
    
    @config = {
      enabled: true,
      storage_path: @test_storage_path,
      async: false  # Use synchronous for testing
    }
    @persistence = SmartPrompt::PersistenceLayer.new(@config)
  end

  def teardown
    # Clean up test data
    @persistence.shutdown if @persistence
    FileUtils.rm_rf(@test_storage_path) if Dir.exist?(@test_storage_path)
  end

  def test_initialization_creates_storage_directory
    assert Dir.exist?(@test_storage_path), "Storage directory should be created"
  end

  def test_initialization_with_disabled_persistence
    persistence = SmartPrompt::PersistenceLayer.new({ enabled: false })
    
    refute persistence.enabled
  end

  def test_save_session
    session = create_test_session("test_session_1")
    
    @persistence.save(session)
    
    file_path = File.join(@test_storage_path, "test_session_1.json")
    assert File.exist?(file_path), "Session file should be created"
  end

  def test_save_creates_valid_json
    session = create_test_session("test_session_2")
    session.add_message({ role: "user", content: "Hello" })
    
    @persistence.save(session)
    
    file_path = File.join(@test_storage_path, "test_session_2.json")
    data = JSON.parse(File.read(file_path), symbolize_names: true)
    
    assert_equal "test_session_2", data[:id]
    assert_equal 1, data[:messages].length
    assert_equal "Hello", data[:messages][0][:content]
  end

  def test_load_session
    session = create_test_session("test_session_3")
    session.add_message({ role: "user", content: "Test message" })
    
    @persistence.save(session)
    loaded_data = @persistence.load("test_session_3")
    
    refute_nil loaded_data
    assert_equal "test_session_3", loaded_data[:id]
    assert_equal 1, loaded_data[:messages].length
    assert_equal "Test message", loaded_data[:messages][0][:content]
  end

  def test_load_nonexistent_session
    result = @persistence.load("nonexistent_session")
    
    assert_nil result
  end

  def test_delete_session
    session = create_test_session("test_session_4")
    @persistence.save(session)
    
    file_path = File.join(@test_storage_path, "test_session_4.json")
    assert File.exist?(file_path)
    
    @persistence.delete("test_session_4")
    
    refute File.exist?(file_path), "Session file should be deleted"
  end

  def test_delete_nonexistent_session
    # Should not raise error
    @persistence.delete("nonexistent_session")
  end

  def test_exists_check
    session = create_test_session("test_session_5")
    
    refute @persistence.exists?("test_session_5")
    
    @persistence.save(session)
    
    assert @persistence.exists?("test_session_5")
  end

  def test_list_sessions
    session1 = create_test_session("session_1")
    session2 = create_test_session("session_2")
    session3 = create_test_session("session_3")
    
    @persistence.save(session1)
    @persistence.save(session2)
    @persistence.save(session3)
    
    sessions = @persistence.list_sessions
    
    assert_equal 3, sessions.length
    assert_includes sessions, "session_1"
    assert_includes sessions, "session_2"
    assert_includes sessions, "session_3"
  end

  def test_list_sessions_empty_directory
    sessions = @persistence.list_sessions
    
    assert_equal 0, sessions.length
  end

  def test_save_with_disabled_persistence
    persistence = SmartPrompt::PersistenceLayer.new({ enabled: false })
    session = create_test_session("test_session_6")
    
    # Should not raise error
    persistence.save(session)
    
    # Should not create file
    refute File.exist?(File.join(@test_storage_path, "test_session_6.json"))
  end

  def test_load_with_disabled_persistence
    persistence = SmartPrompt::PersistenceLayer.new({ enabled: false })
    
    result = persistence.load("any_session")
    
    assert_nil result
  end

  def test_save_async
    session = create_test_session("test_session_7")
    
    # Use async persistence
    async_persistence = SmartPrompt::PersistenceLayer.new(@config.merge(async: true))
    async_persistence.save_async(session)
    
    # Wait a bit for async operation to complete
    sleep 0.1
    
    file_path = File.join(@test_storage_path, "test_session_7.json")
    assert File.exist?(file_path), "Session file should be created asynchronously"
    
    async_persistence.shutdown
  end

  def test_serialization_preserves_metadata
    session = create_test_session("test_session_8")
    session.instance_variable_set(:@metadata, { key: "value", count: 42 })
    session.add_message({ role: "user", content: "Test" })
    
    @persistence.save(session)
    loaded_data = @persistence.load("test_session_8")
    
    assert_equal "value", loaded_data[:metadata][:key]
    assert_equal 42, loaded_data[:metadata][:count]
  end

  def test_serialization_preserves_timestamps
    session = create_test_session("test_session_9")
    
    @persistence.save(session)
    loaded_data = @persistence.load("test_session_9")
    
    refute_nil loaded_data[:created_at]
    refute_nil loaded_data[:updated_at]
    
    # Should be valid ISO8601 timestamps
    assert Time.parse(loaded_data[:created_at])
    assert Time.parse(loaded_data[:updated_at])
  end

  def test_error_handling_on_save_failure
    # Create persistence with invalid path
    invalid_persistence = SmartPrompt::PersistenceLayer.new({
      enabled: true,
      storage_path: "/invalid/path/that/does/not/exist",
      async: false
    })
    
    session = create_test_session("test_session_10")
    
    # Should not raise error, just log it
    invalid_persistence.save(session)
  end

  def test_error_handling_on_load_failure
    # Create a corrupted file
    file_path = File.join(@test_storage_path, "corrupted_session.json")
    File.write(file_path, "{ invalid json }")
    
    result = @persistence.load("corrupted_session")
    
    # Should return nil on error
    assert_nil result
  end

  private

  def create_test_session(session_id)
    SmartPrompt::Session.new(session_id, {})
  end
end
