require 'minitest/autorun'
require 'tempfile'
require './lib/smart_prompt'

class ImageGenerationAdapterTest < Minitest::Test
  def setup
    @config = {
      "api_key" => "test-api-key",
      "url" => "https://api.siliconflow.cn/v1/",
      "model" => "Kwai-Kolors/Kolors",
    }
    @adapter = SmartPrompt::ImageGenerationAdapter.new(@config)
  end

  def test_initialization
    assert_instance_of SmartPrompt::ImageGenerationAdapter, @adapter
  end

  def test_initialization_with_env_string
    ENV["SILICONFLOW_API_KEY"] = "fake-key-for-test"
    adapter = SmartPrompt::ImageGenerationAdapter.new(
      "api_key" => 'ENV["SILICONFLOW_API_KEY"]',
      "url" => "https://api.siliconflow.cn/v1/",
      "model" => "Kwai-Kolors/Kolors",
    )
    assert_instance_of SmartPrompt::ImageGenerationAdapter, adapter
  ensure
    ENV.delete("SILICONFLOW_API_KEY")
  end

  def test_build_parameters_requires_model
    adapter = SmartPrompt::ImageGenerationAdapter.new(
      "api_key" => "k", "url" => "https://x/", "model" => nil
    )
    assert_raises(SmartPrompt::Error) do
      adapter.send(:build_parameters, "a cat", {})
    end
  end

  def test_build_parameters_maps_native_fields
    params = {
      model: "Qwen/Qwen-Image",
      negative_prompt: "blurry",
      seed: 7,
      num_inference_steps: 30,
      guidance_scale: 7.5,
      cfg: 4.0,
    }
    result = @adapter.send(:build_parameters, "a cat", params)
    assert_equal "Qwen/Qwen-Image", result[:model]
    assert_equal "a cat", result[:prompt]
    assert_equal "blurry", result[:negative_prompt]
    assert_equal 7, result[:seed]
    assert_equal 30, result[:num_inference_steps]
    assert_equal 7.5, result[:guidance_scale]
    assert_equal 4.0, result[:cfg]
  end

  def test_build_parameters_omits_nil_optionals
    result = @adapter.send(:build_parameters, "a cat", {})
    assert_equal "Kwai-Kolors/Kolors", result[:model]
    refute result.key?(:negative_prompt)
    refute result.key?(:seed)
    refute result.key?(:cfg)
  end

  def test_resolve_image_size_default
    assert_equal "1024x1024", @adapter.send(:resolve_image_size, {})
  end

  def test_resolve_image_size_alias
    assert_equal "960x1280", @adapter.send(:resolve_image_size, size: "960x1280")
    assert_equal "960x1280", @adapter.send(:resolve_image_size, image_size: "960x1280")
  end

  def test_parse_images_siliconflow_format
    response = { "images" => [{ "url" => "https://x/a.png", "seed" => 42 }] }
    images = @adapter.send(:parse_images, response)
    assert_equal 1, images.size
    assert_equal "https://x/a.png", images.first[:url]
    assert_equal 42, images.first[:seed]
  end

  def test_parse_images_openai_data_fallback
    response = { "data" => [{ "url" => "https://x/a.png" }] }
    images = @adapter.send(:parse_images, response)
    assert_equal "https://x/a.png", images.first[:url]
  end

  def test_parse_images_empty_raises
    assert_raises(SmartPrompt::LLMAPIError) do
      @adapter.send(:parse_images, { "images" => [] })
    end
  end

  def test_normalize_input_image_http_url_passthrough
    url = "https://example.com/cat.jpg"
    assert_equal url, @adapter.send(:normalize_input_image, url)
  end

  def test_normalize_input_image_data_url_passthrough
    data_url = "data:image/png;base64,AAAA"
    assert_equal data_url, @adapter.send(:normalize_input_image, data_url)
  end

  def test_normalize_input_image_from_file
    file = Tempfile.new(["image", ".png"])
    file.binmode
    file.write("PNG-DATA")
    file.close

    result = @adapter.send(:normalize_input_image, file.path)
    assert_match(%r{^data:image/png;base64,}, result)
    # base64 of "PNG-DATA"
    assert_equal "data:image/png;base64,#{Base64.strict_encode64('PNG-DATA')}", result
  ensure
    file&.unlink
  end

  def test_normalize_input_image_unsupported_extension
    file = Tempfile.new(["image", ".tiff"])
    file.close
    assert_raises(SmartPrompt::Error) do
      @adapter.send(:normalize_input_image, file.path)
    end
  ensure
    file&.unlink
  end

  def test_generate_image_builds_request_and_parses_response
    captured = nil
    @adapter.define_singleton_method(:submit_image_request) do |path, params|
      captured = [path, params]
      { "images" => [{ "url" => "https://x/a.png", "seed" => 1 }] }
    end

    images = @adapter.generate_image("a cat", image_size: "1024x1024", batch_size: 2, seed: 5)

    assert_equal "/images/generations", captured[0]
    params = captured[1]
    assert_equal "Kwai-Kolors/Kolors", params[:model]
    assert_equal "a cat", params[:prompt]
    assert_equal "1024x1024", params[:image_size]
    assert_equal 2, params[:batch_size]
    assert_equal 5, params[:seed]
    refute params.key?(:negative_prompt)

    assert_equal 1, images.size
    assert_equal "https://x/a.png", images.first[:url]
  end

  def test_generate_image_accepts_size_and_n_aliases
    captured = nil
    @adapter.define_singleton_method(:submit_image_request) do |path, params|
      captured = params
      { "images" => [{ "url" => "https://x/a.png" }] }
    end

    @adapter.generate_image("a cat", size: "720x1280", n: 3)

    assert_equal "720x1280", captured[:image_size]
    assert_equal 3, captured[:batch_size]
  end

  def test_generate_image_rejects_empty_prompt
    assert_raises(SmartPrompt::Error) { @adapter.generate_image(nil, {}) }
    assert_raises(SmartPrompt::Error) { @adapter.generate_image("   ", {}) }
  end

  def test_edit_image_requires_input_image
    assert_raises(SmartPrompt::Error) { @adapter.edit_image("prompt", {}) }
  end

  def test_edit_image_omits_image_size_and_normalizes_image
    captured = nil
    @adapter.define_singleton_method(:submit_image_request) do |path, params|
      captured = params
      { "images" => [{ "url" => "https://x/a.png" }] }
    end

    @adapter.edit_image("make it night", image: "https://x/src.png", image_size: "1024x1024")

    assert_equal "https://x/src.png", captured[:image]
    refute captured.key?(:image_size), "edit models reject image_size"
  end

  def test_chat_and_embeddings_not_supported
    assert_raises(NotImplementedError) { @adapter.send(:send_request, [], "m") }
    assert_raises(NotImplementedError) { @adapter.send(:embeddings, "t", "m") }
  end
end
