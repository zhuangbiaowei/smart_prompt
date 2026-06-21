require 'minitest/autorun'
require './lib/smart_prompt'

class ZhipuAIAdapterTest < Minitest::Test
  def setup
    @config = { "api_key" => "x.y", "model" => "glm-4-flash", "temperature" => 0.7 }
    @adapter = SmartPrompt::ZhipuAIAdapter.new(@config)
  end

  def test_initialization
    assert_instance_of SmartPrompt::ZhipuAIAdapter, @adapter
  end

  def test_initialization_with_env_variable
    prev = ENV["ZHIPUAI_API_KEY"]
    ENV["ZHIPUAI_API_KEY"] = "id.secret"
    adapter = SmartPrompt::ZhipuAIAdapter.new("api_key" => "ENV['ZHIPUAI_API_KEY']", "model" => "glm-4-flash")
    assert_instance_of SmartPrompt::ZhipuAIAdapter, adapter
  ensure
    ENV["ZHIPUAI_API_KEY"] = prev
  end

  def test_tolerates_missing_api_key_at_init
    adapter = SmartPrompt::ZhipuAIAdapter.new("api_key" => nil, "model" => "glm-4-flash")
    assert_nil adapter.instance_variable_get(:@api_key)
  end

  def test_default_base_url_and_paths
    a = SmartPrompt::ZhipuAIAdapter.new("api_key" => "k", "model" => "m")
    assert_equal "https://open.bigmodel.cn/api/paas/v4", a.instance_variable_get(:@base_url)
    assert_equal "https://open.bigmodel.cn/api/coding/paas/v4", a.instance_variable_get(:@coding_base)
    assert_equal "https://open.bigmodel.cn/api/paas/v4/images/generations", a.instance_variable_get(:@image_url)
    assert_equal "https://open.bigmodel.cn/api/paas/v4/videos/generations", a.instance_variable_get(:@video_url)
    assert_equal "https://open.bigmodel.cn/api/paas/v4/async-result", a.instance_variable_get(:@query_url)
  end

  def test_chat_body_merges_extras_and_temperature
    cfg = { "api_key" => "k", "model" => "glm-4-plus", "temperature" => 0.9, "top_p" => 0.7, "max_tokens" => 512 }
    a = SmartPrompt::ZhipuAIAdapter.new(cfg)
    body = a.send(:build_chat_body, [{ "role" => "user", "content" => "hi" }], nil, 0.5, nil)
    assert_equal 0.9, body["temperature"]       # config wins
    assert_equal 0.7, body["top_p"]
    assert_equal 512, body["max_tokens"]
    refute body.key?("tools")
  end

  def test_chat_body_includes_tools_when_provided
    body = @adapter.send(:build_chat_body, [], "glm-4-flash", nil, [{ "type" => "function", "function" => {} }])
    assert body.key?("tools")
  end

  def test_coding_model_uses_coding_base
    a = SmartPrompt::ZhipuAIAdapter.new("api_key" => "k", "model" => "codegeex-4")
    assert_equal "https://open.bigmodel.cn/api/coding/paas/v4/chat/completions", a.send(:chat_url_for, "codegeex-4")
    assert_equal "https://open.bigmodel.cn/api/paas/v4/chat/completions", a.send(:chat_url_for, "glm-4-flash")
  end

  def test_multimodal_local_file_becomes_data_url
    tmp = Tempfile.new(["zp", ".png"]); tmp.binmode; tmp.write("fakepng"); tmp.close
    msgs = [{
      "role" => "user",
      "content" => [
        { "type" => "text", "text" => "describe" },
        { "type" => "image_url", "image_url" => { "url" => tmp.path } },
        { "type" => "image_url", "image_url" => { "url" => "https://e.com/x.jpg" } },
      ],
    }]
    out = @adapter.send(:process_multimodal_messages, msgs)
    urls = out[0]["content"].select { |c| c["type"] == "image_url" }.map { |c| c["image_url"]["url"] }
    assert urls[0].start_with?("data:image/png;base64,")
    assert_equal "https://e.com/x.jpg", urls[1]
  ensure
    tmp&.unlink
  end

  def test_completion_response_preserves_reasoning_content
    raw = JSON.parse(<<~JSON)
      {"id":"a","object":"chat.completion","created":1,"model":"glm-4-flash",
       "choices":[{"index":0,"message":{"role":"assistant","content":"hi","reasoning_content":"think"},"finish_reason":"stop"}],
       "usage":{"prompt_tokens":3,"completion_tokens":2,"total_tokens":5}}
    JSON
    resp = @adapter.send(:build_completion_response, raw)
    assert_equal "hi", resp.dig("choices", 0, "message", "content")
    assert_equal "think", resp.dig("choices", 0, "message", "reasoning_content")
  end

  def test_stream_chunk_passes_through_reasoning_and_content
    chunk = @adapter.send(:build_stream_chunk, JSON.parse(
      '{"id":"x","choices":[{"index":0,"delta":{"content":"你","reasoning_content":"想"},"finish_reason":""}]}'))
    assert_equal "你", chunk.dig("choices", 0, "delta", "content")
    assert_equal "想", chunk.dig("choices", 0, "delta", "reasoning_content")
  end

  def test_parse_nested_image_response
    # Zhipu nests images under data.images[]
    raw = { "created" => 1, "data" => { "images" => [{ "url" => "https://x/a.png" }] } }
    images = @adapter.send(:parse_image_response, raw)
    assert_equal 1, images.size
    assert_equal "https://x/a.png", images[0][:url]
  end

  def test_parse_image_response_bare_url_array
    raw = { "data" => { "images" => ["https://x/a.png", "https://x/b.png"] } }
    images = @adapter.send(:parse_image_response, raw)
    assert_equal 2, images.size
    assert_equal "https://x/b.png", images[1][:url]
  end

  def test_video_status_and_url_helpers
    # video_result is an Array: [{cover_image_url:, url:}]
    success = { "task_status" => "SUCCESS",
                "video_result" => [{ "url" => "https://v/x.mp4", "cover_image_url" => "https://v/c.png" }] }
    assert_equal "SUCCESS", @adapter.send(:task_status_of, success)
    assert_equal "https://v/x.mp4", @adapter.send(:video_url_of, success)
    assert_equal "https://v/c.png", @adapter.send(:cover_url_of, success)

    processing = { "task_status" => "PROCESSING" }
    assert_equal "PROCESSING", @adapter.send(:task_status_of, processing)
  end

  def test_generate_image_requires_prompt
    assert_raises(SmartPrompt::Error) { @adapter.generate_image("   ") }
  end

  def test_generate_video_requires_model
    a = SmartPrompt::ZhipuAIAdapter.new("api_key" => "k", "model" => nil)
    # No model -> raises before any network call
    assert_raises(SmartPrompt::Error) { a.generate_video("prompt", {}) }
  end
end
