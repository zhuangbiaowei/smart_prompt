require 'minitest/autorun'
require './lib/smart_prompt'
require_relative 'test_helper'

class SiliconFlowAdapterTest < Minitest::Test
  def setup
    @config = { "api_key" => "sk-test", "model" => "Qwen/Qwen2.5-7B-Instruct", "temperature" => 0.7 }
    @adapter = SmartPrompt::SiliconFlowAdapter.new(@config)
  end

  def test_initialization
    assert_instance_of SmartPrompt::SiliconFlowAdapter, @adapter
  end

  def test_initialization_with_env_variable
    prev = ENV["SILICONFLOW_API_KEY"]
    ENV["SILICONFLOW_API_KEY"] = "sk-env"
    adapter = SmartPrompt::SiliconFlowAdapter.new("api_key" => "ENV['SILICONFLOW_API_KEY']", "model" => "Qwen/Qwen2.5-7B-Instruct")
    assert_instance_of SmartPrompt::SiliconFlowAdapter, adapter
  ensure
    ENV["SILICONFLOW_API_KEY"] = prev
  end

  def test_tolerates_missing_api_key_at_init
    adapter = SmartPrompt::SiliconFlowAdapter.new("api_key" => nil, "model" => "m")
    assert_nil adapter.instance_variable_get(:@api_key)
  end

  def test_default_base_url_and_paths
    a = SmartPrompt::SiliconFlowAdapter.new("api_key" => "k", "model" => "m")
    assert_equal "https://api.siliconflow.cn/v1", a.instance_variable_get(:@base_url)
    assert_equal "https://api.siliconflow.cn/v1/images/generations",   a.instance_variable_get(:@image_url)
    assert_equal "https://api.siliconflow.cn/v1/video/submit",         a.instance_variable_get(:@video_submit_url)
    assert_equal "https://api.siliconflow.cn/v1/video/status",         a.instance_variable_get(:@video_status_url)
    assert_equal "https://api.siliconflow.cn/v1/audio/speech",         a.instance_variable_get(:@speech_url)
    assert_equal "https://api.siliconflow.cn/v1/audio/transcriptions", a.instance_variable_get(:@transcription_url)
    assert_equal "https://api.siliconflow.cn/v1/uploads/audio/voice",  a.instance_variable_get(:@voice_upload_url)
    assert_equal "https://api.siliconflow.cn/v1/audio/voice/list",     a.instance_variable_get(:@voice_list_url)
    assert_equal "https://api.siliconflow.cn/v1/audio/voice/deletions",a.instance_variable_get(:@voice_delete_url)
  end

  def test_chat_body_merges_extras_and_temperature
    cfg = { "api_key" => "k", "model" => "deepseek-ai/DeepSeek-R1", "temperature" => 0.9,
            "top_p" => 0.95, "max_tokens" => 512, "enable_thinking" => true }
    a = SmartPrompt::SiliconFlowAdapter.new(cfg)
    body = a.send(:build_chat_body, [{ "role" => "user", "content" => "hi" }], nil, 0.5, nil)
    assert_equal 0.9, body["temperature"]        # config wins over arg
    assert_equal 0.95, body["top_p"]
    assert_equal 512, body["max_tokens"]
    assert body["enable_thinking"]
    refute body.key?("tools")
  end

  def test_chat_body_includes_tools_when_provided
    body = @adapter.send(:build_chat_body, [], "Qwen/Qwen2.5-7B-Instruct", nil, [{ "type" => "function", "function" => {} }])
    assert body.key?("tools")
  end

  def test_multimodal_local_file_becomes_data_url
    tmp = Tempfile.new(["sf", ".png"]); tmp.binmode; tmp.write("fakepng"); tmp.close
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
      {"id":"a","object":"chat.completion","created":1,"model":"deepseek-ai/DeepSeek-R1",
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

  def test_parse_image_response_images_url
    # SiliconFlow returns images[].url (FLAT, not nested data[]).
    raw = { "images" => [{ "url" => "https://x/a.png" }, { "url" => "https://x/b.png" }] }
    images = @adapter.send(:parse_image_response, raw)
    assert_equal 2, images.size
    assert_equal "https://x/a.png", images[0][:url]
    assert_equal "https://x/b.png", images[1][:url]
  end

  def test_parse_image_response_bare_url_array
    raw = { "images" => ["https://x/a.png", "https://x/b.png"] }
    images = @adapter.send(:parse_image_response, raw)
    assert_equal 2, images.size
    assert_equal "https://x/b.png", images[1][:url]
  end

  def test_parse_image_response_empty_raises
    assert_raises(SmartPrompt::LLMAPIError) { @adapter.send(:parse_image_response, { "images" => [] }) }
  end

  def test_video_status_and_url_helpers
    # results is an OBJECT (not array); url at results.videos[].url.
    success = { "status" => "Succeed",
                "results" => { "videos" => [{ "url" => "https://v/x.mp4" }] } }
    assert_equal "Succeed", @adapter.send(:video_status_of, success)
    assert_equal "https://v/x.mp4", @adapter.send(:video_url_of, success)

    processing = { "status" => "InQueue" }
    assert_equal "InQueue", @adapter.send(:video_status_of, processing)
  end

  def test_parse_rerank_response_relevance_score
    raw = { "results" => [
      { "index" => 1, "relevance_score" => 0.98 },
      { "index" => 0, "relevance_score" => 0.41 },
    ] }
    out = @adapter.send(:parse_rerank_response, raw)
    assert_equal 2, out.size
    assert_equal({ index: 1, relevance_score: 0.98 }, out[0])
    assert_equal 0.41, out[1][:relevance_score]
  end

  def test_parse_rerank_response_falls_back_to_score
    raw = { "results" => [{ "index" => 0, "score" => 0.5 }] }
    out = @adapter.send(:parse_rerank_response, raw)
    assert_equal 0.5, out[0][:relevance_score]
  end

  def test_resolve_video_size_default_and_unknown
    assert_equal "1280x720", @adapter.send(:resolve_video_size, nil)
    assert_equal "1280x720", @adapter.send(:resolve_video_size, "")
    # Unknown sizes are passed through (with a warning) rather than rejected.
    assert_equal "999x999", @adapter.send(:resolve_video_size, "999x999")
  end

  def test_generate_image_requires_prompt
    assert_raises(SmartPrompt::Error) { @adapter.generate_image("   ") }
  end

  def test_generate_image_requires_model
    a = SmartPrompt::SiliconFlowAdapter.new("api_key" => "k", "model" => nil)
    assert_raises(SmartPrompt::Error) { a.generate_image("a cat", {}) }
  end

  def test_generate_video_requires_model
    a = SmartPrompt::SiliconFlowAdapter.new("api_key" => "k", "model" => nil)
    # No model -> raises before any network call
    assert_raises(SmartPrompt::Error) { a.generate_video("prompt", {}) }
  end

  def test_normalize_input_image_accepts_url
    assert_equal "https://e.com/x.jpg", @adapter.send(:normalize_input_image, "https://e.com/x.jpg")
    assert_equal "data:image/png;base64,AAAA", @adapter.send(:normalize_input_image, "data:image/png;base64,AAAA")
  end

  def test_send_request_keeps_five_params
    # conversation.rb routes request_options on parameters.length >= 6; must stay 5.
    assert_equal 5, SmartPrompt::SiliconFlowAdapter.instance_method(:send_request).parameters.length
  end

  def test_embeddings_raises_when_no_vector
    with_stub_method(@adapter, :http_post_json, { "data" => [] }) do
      assert_raises(SmartPrompt::LLMAPIError) { @adapter.embeddings("text", "BAAI/bge-m3") }
    end
  end
end
