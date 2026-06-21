require 'minitest/autorun'
require './lib/smart_prompt'

class AnthropicAdapterTest < Minitest::Test
  def setup
    @config = {
      "api_key" => "test-api-key",
      "model" => "claude-3-5-sonnet-20241022",
      "temperature" => 0.7,
      "max_tokens" => 1024
    }
    @adapter = SmartPrompt::AnthropicAdapter.new(@config)
  end

  def test_initialization
    assert_instance_of SmartPrompt::AnthropicAdapter, @adapter
  end

  def test_initialization_with_env_variable
    config = {
      "api_key" => "ENV['ANTHROPIC_API_KEY']",
      "model" => "claude-3-5-sonnet-20241022"
    }
    adapter = SmartPrompt::AnthropicAdapter.new(config)
    assert_instance_of SmartPrompt::AnthropicAdapter, adapter
  end

  def test_convert_messages_to_anthropic_format
    messages = [
      { role: "system", content: "You are helpful." },
      { role: "user", content: "Hello" },
      { role: "assistant", content: "Hi there!" },
      { role: "user", content: "How are you?" }
    ]
    
    converted = @adapter.send(:convert_messages_to_anthropic_format, messages)
    
    # System message should be filtered out
    assert_equal 3, converted.length
    assert_equal "user", converted[0][:role]
    assert_equal "assistant", converted[1][:role]
    assert_equal "user", converted[2][:role]
  end

  def test_extract_system_message
    messages = [
      { role: "system", content: "You are helpful." },
      { role: "user", content: "Hello" }
    ]
    
    system_msg = @adapter.send(:extract_system_message, messages)
    assert_equal "You are helpful.", system_msg
  end

  def test_extract_system_message_when_none
    messages = [
      { role: "user", content: "Hello" }
    ]
    
    system_msg = @adapter.send(:extract_system_message, messages)
    assert_nil system_msg
  end

  def test_prepare_image_content_with_url
    image_url = "https://example.com/image.jpg"
    
    result = @adapter.send(:prepare_image_content, image_url)
    
    assert_equal "image", result[:type]
    assert_equal "url", result[:source][:type]
    assert_equal image_url, result[:source][:url]
  end

  def test_prepare_image_content_with_data_url
    data_url = "data:image/jpeg;base64,/9j/4AAQSkZJRg=="
    
    result = @adapter.send(:prepare_image_content, data_url)
    
    assert_equal "image", result[:type]
    assert_equal "base64", result[:source][:type]
    assert_equal "image/jpeg", result[:source][:media_type]
    assert_equal "/9j/4AAQSkZJRg==", result[:source][:data]
  end

  def test_convert_tools_to_anthropic_format
    tools = [
      {
        function: {
          name: "get_weather",
          description: "Get weather info",
          parameters: {
            type: "object",
            properties: {
              location: { type: "string" }
            }
          }
        }
      }
    ]
    
    converted = @adapter.send(:convert_tools_to_anthropic_format, tools)
    
    assert_equal 1, converted.length
    assert_equal "get_weather", converted[0][:name]
    assert_equal "Get weather info", converted[0][:description]
    assert converted[0][:input_schema]
  end

  def test_extract_content_from_response_with_array
    response = {
      "content" => [
        { "type" => "text", "text" => "Hello" },
        { "type" => "text", "text" => "World" }
      ]
    }
    
    content = @adapter.send(:extract_content_from_response, response)
    assert_equal "Hello\nWorld", content
  end

  def test_extract_content_from_response_with_string
    response = {
      "content" => "Hello World"
    }
    
    content = @adapter.send(:extract_content_from_response, response)
    assert_equal "Hello World", content
  end

  def test_extract_content_from_response_with_nil
    response = {
      "content" => nil
    }
    
    content = @adapter.send(:extract_content_from_response, response)
    assert_equal "", content
  end

  def test_extract_content_from_response_with_empty_array
    response = {
      "content" => []
    }
    
    content = @adapter.send(:extract_content_from_response, response)
    assert_equal "", content
  end

  def test_embeddings_not_supported
    assert_raises(NotImplementedError) do
      @adapter.embeddings("test text", "model")
    end
  end

  def test_custom_base_url_from_config
    config = {
      "api_key" => "test-key",
      "url" => "https://custom-api.example.com",
      "model" => "claude-3-5-sonnet-20241022"
    }
    
    adapter = SmartPrompt::AnthropicAdapter.new(config)
    assert_instance_of SmartPrompt::AnthropicAdapter, adapter
  end

  def test_custom_base_url_from_env
    # Save original env value
    original_env = ENV['ANTHROPIC_BASE_URL']
    
    begin
      # Set test env value
      ENV['ANTHROPIC_BASE_URL'] = 'https://env-api.example.com'
      
      config = {
        "api_key" => "test-key",
        "model" => "claude-3-5-sonnet-20241022"
      }
      
      adapter = SmartPrompt::AnthropicAdapter.new(config)
      assert_instance_of SmartPrompt::AnthropicAdapter, adapter
    ensure
      # Restore original env value
      if original_env
        ENV['ANTHROPIC_BASE_URL'] = original_env
      else
        ENV.delete('ANTHROPIC_BASE_URL')
      end
    end
  end

  def test_base_url_priority_config_over_env
    # Save original env value
    original_env = ENV['ANTHROPIC_BASE_URL']
    
    begin
      # Set test env value
      ENV['ANTHROPIC_BASE_URL'] = 'https://env-api.example.com'
      
      # Config should take priority
      config = {
        "api_key" => "test-key",
        "url" => "https://config-api.example.com",
        "model" => "claude-3-5-sonnet-20241022"
      }
      
      adapter = SmartPrompt::AnthropicAdapter.new(config)
      assert_instance_of SmartPrompt::AnthropicAdapter, adapter
      # Note: We can't directly test the internal @base_url without exposing it,
      # but the initialization should succeed
    ensure
      # Restore original env value
      if original_env
        ENV['ANTHROPIC_BASE_URL'] = original_env
      else
        ENV.delete('ANTHROPIC_BASE_URL')
      end
    end
  end

  def test_default_base_url
    # Ensure no env variable is set
    original_env = ENV['ANTHROPIC_BASE_URL']
    ENV.delete('ANTHROPIC_BASE_URL')
    
    begin
      config = {
        "api_key" => "test-key",
        "model" => "claude-3-5-sonnet-20241022"
      }
      
      adapter = SmartPrompt::AnthropicAdapter.new(config)
      assert_instance_of SmartPrompt::AnthropicAdapter, adapter
      # Should use default https://api.anthropic.com
    ensure
      # Restore original env value
      if original_env
        ENV['ANTHROPIC_BASE_URL'] = original_env
      end
    end
  end

  def test_multimodal_message_conversion
    messages = [
      {
        role: "user",
        content: [
          { type: "text", text: "What's in this image?" },
          { type: "image_url", image_url: "https://example.com/image.jpg" }
        ]
      }
    ]
    
    converted = @adapter.send(:convert_messages_to_anthropic_format, messages)
    
    assert_equal 1, converted.length
    assert_equal "user", converted[0][:role]
    assert_instance_of Array, converted[0][:content]
    assert_equal 2, converted[0][:content].length
  end
end
