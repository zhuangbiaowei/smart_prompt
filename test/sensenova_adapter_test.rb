require 'minitest/autorun'
require './lib/smart_prompt'

class SenseNovaAdapterTest < Minitest::Test
  def setup
    @config = {
      "api_key" => "test-api-key",
      "model" => "SenseChat-5",
      "temperature" => 0.7
    }
    @adapter = SmartPrompt::SenseNovaAdapter.new(@config)
  end

  def test_initialization
    assert_instance_of SmartPrompt::SenseNovaAdapter, @adapter
  end

  def test_initialization_with_env_variable
    prev = ENV["SENSENOVA_API_KEY"]
    ENV["SENSENOVA_API_KEY"] = "env-key"
    config = { "api_key" => "ENV['SENSENOVA_API_KEY']", "model" => "SenseChat-5" }
    adapter = SmartPrompt::SenseNovaAdapter.new(config)
    assert_instance_of SmartPrompt::SenseNovaAdapter, adapter
  ensure
    ENV["SENSENOVA_API_KEY"] = prev
  end

  def test_default_base_urls
    adapter = SmartPrompt::SenseNovaAdapter.new("api_key" => "k", "model" => "m")
    assert_equal "https://api.sensenova.cn/compatible-mode/v2", adapter.instance_variable_get(:@base_url)
    assert_equal "https://api.sensenova.cn/v1/llm/embeddings", adapter.instance_variable_get(:@embeddings_url)
    assert_equal "https://token.sensenova.cn/v1/images/generations", adapter.instance_variable_get(:@image_url)
  end

  def test_tolerates_missing_api_key_at_init
    # Like the other adapters, construction must not raise when the key is unset so that
    # examples / config can load without a live key. The key is validated on first request.
    adapter = SmartPrompt::SenseNovaAdapter.new("api_key" => nil, "model" => "m")
    assert_nil adapter.instance_variable_get(:@api_key)
  end

  def test_chat_body_merges_config_extras_and_temperature
    config = {
      "api_key" => "k", "model" => "SenseChat-5", "temperature" => 0.8,
      "reasoning_effort" => "medium", "max_completion_tokens" => 2048, "top_p" => 0.7
    }
    adapter = SmartPrompt::SenseNovaAdapter.new(config)
    body = adapter.send(:build_chat_body, [{ "role" => "user", "content" => "hi" }], nil, 0.5, nil)
    # config temperature wins over the per-call argument
    assert_equal 0.8, body["temperature"]
    assert_equal "medium", body["reasoning_effort"]
    assert_equal 2048, body["max_completion_tokens"]
    assert_equal 0.7, body["top_p"]
    refute body.key?("tools")
  end

  def test_chat_body_includes_tools_when_provided
    body = @adapter.send(:build_chat_body, [], "SenseChat-5", nil, [{ "type" => "function", "function" => {} }])
    assert body.key?("tools")
  end

  def test_multimodal_local_file_becomes_data_url
    tmp = Tempfile.new(["sn", ".png"]); tmp.binmode; tmp.write("fakepng"); tmp.close
    msgs = [{
      "role" => "user",
      "content" => [
        { "type" => "text", "text" => "describe" },
        { "type" => "image_url", "image_url" => { "url" => tmp.path } },
        { "type" => "image_url", "image_url" => { "url" => "https://example.com/x.jpg" } }
      ]
    }]
    out = @adapter.send(:process_multimodal_messages, msgs)
    image_urls = out[0]["content"].select { |c| c["type"] == "image_url" }.map { |c| c["image_url"]["url"] }
    assert image_urls[0].start_with?("data:image/png;base64,")
    assert_equal "https://example.com/x.jpg", image_urls[1]
  ensure
    tmp&.unlink
  end

  def test_completion_response_surfaces_reasoning
    raw = JSON.parse(<<~JSON)
      {"id":"abc","object":"chat.completion","created":1,"model":"SenseChat-5",
       "choices":[{"index":0,"message":{"role":"assistant","content":"hi","reasoning":"think"},"finish_reason":"stop"}],
       "usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}
    JSON
    resp = @adapter.send(:build_completion_response, raw)
    assert_equal "hi", resp.dig("choices", 0, "message", "content")
    assert_equal "think", resp.dig("choices", 0, "message", "reasoning_content")
    assert_equal 5, resp.dig("usage", "total_tokens")
  end

  def test_stream_chunk_remaps_reasoning_and_forwards_content
    reasoning = @adapter.send(:build_stream_chunk, JSON.parse(
      '{"id":"x","model":"SenseChat-5","choices":[{"index":0,"delta":{"reasoning":"想"},"finish_reason":""}]}'))
    assert_equal "想", reasoning.dig("choices", 0, "delta", "reasoning_content")

    content = @adapter.send(:build_stream_chunk, JSON.parse(
      '{"id":"x","choices":[{"index":0,"delta":{"content":"你"},"finish_reason":""}]}'))
    assert_equal "你", content.dig("choices", 0, "delta", "content")
  end

  def test_stream_chunk_usage_only_event_has_empty_choices
    chunk = @adapter.send(:build_stream_chunk, JSON.parse(
      '{"id":"x","choices":[],"usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}'))
    assert_equal [], chunk["choices"]
    assert_equal 5, chunk.dig("usage", "total_tokens")
  end

  def test_generate_image_requires_prompt
    assert_raises(SmartPrompt::Error) { @adapter.generate_image("   ") }
  end

  def test_resolve_image_size_defaults_and_warns
    assert_equal "2048x2048", @adapter.send(:resolve_image_size, nil)
    assert_equal "2048x2048", @adapter.send(:resolve_image_size, "")
    # A valid size passes through unchanged
    assert_equal "1536x2752", @adapter.send(:resolve_image_size, "1536x2752")
    # An out-of-list size is still returned (the API will reject it) but logs a warning
    assert_equal "1024x1024", @adapter.send(:resolve_image_size, "1024x1024")
  end
end
