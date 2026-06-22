require 'minitest/autorun'
require 'base64'
require 'tempfile'
require './lib/smart_prompt'

# Direct tests for the MultimodalMessages concern. Focuses on the branches no adapter
# test reaches: video_url/audio_url, preserving detail/max_frames/fps, and the audio/
# video/error paths of normalize_media_url.
class MultimodalMessagesConcernTest < Minitest::Test
  class Holder
    include SmartPrompt::MultimodalMessages
  end

  def setup
    @m = Holder.new
  end

  def tmp(name)
    t = Tempfile.new(name); t.binmode; yield t; t.close(true)
  end

  # ---- process_multimodal_messages ------------------------------------------

  def test_process_passes_through_string_content
    out = @m.process_multimodal_messages([{ "role" => "user", "content" => "hi" }])
    assert_equal "hi", out[0]["content"]
  end

  def test_process_normalizes_array_content
    out = @m.process_multimodal_messages([{
      "role" => "user",
      "content" => [{ "type" => "text", "text" => "q" }, { "type" => "image_url", "image_url" => { "url" => "https://e/x.jpg" } }],
    }])
    assert_equal "q", out[0]["content"][0]["text"]
    assert_equal "https://e/x.jpg", out[0]["content"][1]["image_url"]["url"]
  end

  # ---- normalize_content_item -----------------------------------------------

  def test_normalize_non_hash_becomes_text
    assert_equal({ "type" => "text", "text" => "plain" }, @m.normalize_content_item("plain"))
  end

  def test_normalize_image_url_local_file_becomes_data_url
    tmp(["mm", ".png"]) do |t| t.write("fakepng")
      out = @m.normalize_content_item({ "type" => "image_url", "image_url" => { "url" => t.path } })
      assert out["image_url"]["url"].start_with?("data:image/png;base64,")
    end
  end

  def test_normalize_video_url_preserves_detail_max_frames_fps
    out = @m.normalize_content_item({
      "type" => "video_url",
      "video_url" => { "url" => "https://e/v.mp4", "detail" => "high", "max_frames" => 16, "fps" => 2 },
    })
    part = out["video_url"]
    assert_equal "https://e/v.mp4", part["url"]      # url inlined unchanged
    assert_equal "high", part["detail"]              # extra keys preserved
    assert_equal 16, part["max_frames"]
    assert_equal 2, part["fps"]
  end

  def test_normalize_audio_url_inlines_local_file
    tmp(["mm", ".wav"]) do |t| t.write("wavaudio")
      out = @m.normalize_content_item({ "type" => "audio_url", "audio_url" => { "url" => t.path } })
      assert out["audio_url"]["url"].start_with?("data:audio/wav;base64,")
    end
  end

  def test_normalize_unknown_type_falls_through_to_stringify
    out = @m.normalize_content_item({ "type" => "text", "text" => "x", "extra" => 1 })
    assert_equal({ "type" => "text", "text" => "x", "extra" => 1 }, out)
  end

  # ---- normalize_media_part bare-string url ---------------------------------

  def test_normalize_media_part_accepts_bare_string_url
    out = @m.normalize_content_item({ "type" => "image_url", "image_url" => "https://e/bare.jpg" })
    assert_equal "https://e/bare.jpg", out["image_url"]["url"]
  end

  # ---- normalize_media_url --------------------------------------------------

  def test_normalize_media_url_passes_through_http_and_data
    assert_equal "https://e/x", @m.normalize_media_url("https://e/x", :image)
    assert_equal "data:image/png;base64,QQ==", @m.normalize_media_url("data:image/png;base64,QQ==", :image)
    assert_nil @m.normalize_media_url(nil, :image)
  end

  def test_normalize_media_url_video_branch_inlines_local_file
    tmp(["mm", ".mp4"]) do |t| t.write("mp4data")
      url = @m.normalize_media_url(t.path, :video)
      assert url.start_with?("data:video/mp4;base64,")
    end
  end

  def test_normalize_media_url_missing_file_raises
    assert_raises(SmartPrompt::Error) { @m.normalize_media_url("/no/such/file.png", :image) }
  end

  def test_normalize_media_url_unsupported_image_format_raises
    tmp(["mm", ".tiff"]) do |t| t.write("x")
      err = assert_raises(SmartPrompt::Error) { @m.normalize_media_url(t.path, :image) }
      assert_match(/Unsupported image format/, err.message)
    end
  end

  # ---- normalize_input_image ------------------------------------------------

  def test_normalize_input_image_nil_passes_through
    assert_nil @m.normalize_input_image(nil)
  end

  def test_normalize_input_image_missing_file_raises
    assert_raises(SmartPrompt::Error) { @m.normalize_input_image("/no/such.png") }
  end

  # ---- normalize_image_url shim --------------------------------------------

  def test_normalize_image_url_shim_equivalent_to_media_url_image
    assert_equal "https://e/x", @m.normalize_image_url("https://e/x")
  end

  # ---- stringify_hash -------------------------------------------------------

  def test_stringify_hash_recurses_nested
    out = @m.stringify_hash({ a: { b: [1, { c: 2 }] } })
    assert_equal({ "a" => { "b" => [1, { "c" => 2 }] } }, out)
  end
end
