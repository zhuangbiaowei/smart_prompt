require 'minitest/autorun'
require 'base64'
require 'fileutils'
require 'tmpdir'
require 'net/http'
require_relative '../test_helper'
require './lib/smart_prompt'

# Direct tests for the ImagePersistence concern — previously zero coverage despite
# containing filesystem writes, a network GET, and binary decoding.
class ImagePersistenceConcernTest < Minitest::Test
  include NetHTTPStub

  class Persister
    include SmartPrompt::ImagePersistence

    def provider_label; "Test"; end
    def default_image_prefix; "test_image"; end
  end

  # get_response double: responds to []("content-type"), body, is_a?, code.
  class FakeImageResponse
    def initialize(success: true, content_type: "image/png", body: "imgbytes")
      @success = success
      @content_type = content_type
      @body = body
    end

    def is_a?(klass)
      return true if @success && klass == Net::HTTPSuccess
      super
    end

    def [](key); key == "content-type" ? @content_type : nil; end
    def body; @body; end
    def code; @success ? "200" : "404"; end
  end

  def setup
    @p = Persister.new
  end

  def test_save_image_writes_each_item_in_array
    Dir.mktmpdir do |dir|
      images = [
        { b64_json: Base64.strict_encode64("png1") },
        { b64_json: Base64.strict_encode64("png2") },
      ]
      saved = @p.save_image(images, dir, "img")
      assert_equal 2, saved.size
      assert File.exist?(File.join(dir, "img_1.png"))
      assert File.exist?(File.join(dir, "img_2.png"))
      assert_equal "png1", File.binread(File.join(dir, "img_1.png"))
    end
  end

  def test_save_image_accepts_single_hash
    Dir.mktmpdir do |dir|
      saved = @p.save_image({ b64_json: Base64.strict_encode64("solo") }, dir, "x")
      assert_equal 1, saved.size
      assert File.exist?(File.join(dir, "x_1.png"))
    end
  end

  def test_save_image_uses_default_prefix_when_none_given
    Dir.mktmpdir do |dir|
      @p.save_image({ b64_json: Base64.strict_encode64("d") }, dir)
      assert File.exist?(File.join(dir, "test_image_1.png"))
    end
  end

  def test_save_single_image_b64_writes_png
    Dir.mktmpdir do |dir|
      path = @p.save_single_image({ b64_json: Base64.strict_encode64("DATA") }, dir, "n")
      assert_equal File.join(dir, "n.png"), path
      assert_equal "DATA", File.binread(path)
    end
  end

  def test_save_single_image_url_maps_content_type_to_extension
    [
      ["image/jpeg", "jpg"], ["image/jpg", "jpg"], ["image/png", "png"],
      ["image/gif", "gif"], ["image/webp", "webp"], ["image/avif", "png"], # unknown -> png
    ].each_with_index do |(ct, ext), i|
      Dir.mktmpdir do |dir|
        resp = FakeImageResponse.new(content_type: ct, body: "b#{i}")
        path = with_http_get_response(resp) do
          @p.save_single_image({ url: "https://h/#{i}" }, dir, "n")
        end
        assert_equal File.join(dir, "n.#{ext}"), path
        assert_equal "b#{i}", File.binread(path)
      end
    end
  end

  def test_save_single_image_url_failed_download_raises
    Dir.mktmpdir do |dir|
      assert_raises(SmartPrompt::Error) do
        with_http_get_response(FakeImageResponse.new(success: false)) do
          @p.save_single_image({ url: "https://h/x" }, dir, "n")
        end
      end
    end
  end

  def test_save_single_image_no_data_raises
    Dir.mktmpdir do |dir|
      assert_raises(SmartPrompt::Error) { @p.save_single_image({}, dir, "n") }
    end
  end
end
