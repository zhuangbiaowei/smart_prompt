require 'minitest/autorun'
require 'net/http'
require 'json'
require 'tempfile'
require_relative '../test_helper'
require './lib/smart_prompt'

# Direct tests for the shared HTTPClient concern. Net::HTTP is stubbed (see
# test_helper) so nothing touches the network — these lock down the stream_chat
# state machine, multipart boundary construction, and the error branches that no
# adapter test reaches.
class HTTPClientConcernTest < Minitest::Test
  include NetHTTPStub

  # ---- test doubles --------------------------------------------------------

  class FakeResponse
    def initialize(success: true, body: "", code: "200")
      @success = success
      @body = body
      @code = code
    end

    def is_a?(klass)
      return true if @success && klass == Net::HTTPSuccess
      super
    end

    attr_reader :body, :code
  end

  class FakeHTTP
    attr_accessor :use_ssl, :open_timeout, :read_timeout
    attr_reader :last_request

    def initialize(response)
      @response = response
    end

    def request(req)
      @last_request = req
      @response
    end
  end

  class FakeStreamResponse
    def initialize(segments, success: true)
      @segments = segments
      @success = success
    end

    def is_a?(klass)
      return true if @success && klass == Net::HTTPSuccess
      super
    end

    def read_body
      @segments.each { |s| yield s }
    end

    def body; "err-body"; end
    def code; "500"; end
  end

  class FakeStreamHTTP
    attr_accessor :use_ssl, :open_timeout, :read_timeout

    def initialize(response)
      @response = response
    end

    def request(_req)
      yield @response
    end
  end

  # ---- holder that mixes in the concern -------------------------------------

  class Holder
    include SmartPrompt::HTTPClient

    def initialize(api_key = "test-key")
      @api_key = api_key
    end

    def provider_label
      "Test"
    end
  end

  def setup
    @client = Holder.new
  end

  # ---- http_post_json -------------------------------------------------------

  def test_post_json_parses_json_body
    result = with_http_new(FakeHTTP.new(FakeResponse.new(body: '{"ok":1}'))) do
      @client.http_post_json("https://h/p", { "a" => 1 })
    end
    assert_equal({ "ok" => 1 }, result)
  end

  def test_post_json_empty_body_returns_empty_hash
    result = with_http_new(FakeHTTP.new(FakeResponse.new(body: ""))) do
      @client.http_post_json("https://h/p", {})
    end
    assert_equal({}, result)
  end

  def test_post_json_sets_auth_and_content_type_headers
    fake = FakeHTTP.new(FakeResponse.new(body: '{}'))
    with_http_new(fake) { @client.http_post_json("https://h/p", { "a" => 1 }) }
    assert_equal "Bearer test-key", fake.last_request["Authorization"]
    assert_equal "application/json", fake.last_request["Content-Type"]
    assert_equal({ "a" => 1 }, JSON.parse(fake.last_request.body))
  end

  def test_post_json_non_2xx_raises_with_provider_label
    fake = FakeHTTP.new(FakeResponse.new(success: false, body: "boom", code: "500"))
    err = assert_raises(SmartPrompt::LLMAPIError) do
      with_http_new(fake) { @client.http_post_json("https://h/p", {}) }
    end
    assert_match(/Test API error: 500 - boom/, err.message)
  end

  # ---- http_get_json --------------------------------------------------------

  def test_get_json_parses_and_uses_bearer
    fake = FakeHTTP.new(FakeResponse.new(body: '{"x":2}'))
    result = with_http_new(fake) { @client.http_get_json("https://h/p") }
    assert_equal({ "x" => 2 }, result)
    assert_equal "Bearer test-key", fake.last_request["Authorization"]
  end

  def test_get_json_empty_body_returns_empty_hash
    result = with_http_new(FakeHTTP.new(FakeResponse.new(body: ""))) { @client.http_get_json("https://h/p") }
    assert_equal({}, result)
  end

  def test_get_json_non_2xx_raises
    fake = FakeHTTP.new(FakeResponse.new(success: false, code: "404"))
    assert_raises(SmartPrompt::LLMAPIError) do
      with_http_new(fake) { @client.http_get_json("https://h/p") }
    end
  end

  # ---- http_post_binary -----------------------------------------------------

  def test_post_binary_returns_raw_body
    result = with_http_new(FakeHTTP.new(FakeResponse.new(body: "\x00\x01raw-audio"))) do
      @client.http_post_binary("https://h/p", {})
    end
    assert_equal "\x00\x01raw-audio", result
  end

  def test_post_binary_non_2xx_raises_tts_message
    fake = FakeHTTP.new(FakeResponse.new(success: false, code: "500"))
    err = assert_raises(SmartPrompt::LLMAPIError) do
      with_http_new(fake) { @client.http_post_binary("https://h/p", {}) }
    end
    assert_match(/Test TTS API error/, err.message)
  end

  # ---- http_post_multipart --------------------------------------------------

  def test_post_multipart_builds_boundary_and_form_data
    tmp = Tempfile.new(["m", ".txt"]); tmp.binmode; tmp.write("hello"); tmp.close
    fake = FakeHTTP.new(FakeResponse.new(body: '{"ok":1}'))
    result = with_http_new(fake) do
      @client.http_post_multipart("https://h/p", { "model" => "m" }, "file", tmp.path, "text/plain")
    end
    assert_equal({ "ok" => 1 }, result)
    body = fake.last_request.body
    assert_match(/----SmartPrompt/, body)    # boundary marker
    assert_includes body, 'name="model"'     # form field
    assert_includes body, 'name="file"'      # file field
    assert_includes body, "hello"            # file content
    assert_includes body, "text/plain"       # file mime
  ensure
    tmp&.unlink
  end

  def test_post_multipart_non_2xx_raises_multipart_message
    tmp = Tempfile.new(["m", ".txt"]); tmp.write("x"); tmp.close
    fake = FakeHTTP.new(FakeResponse.new(success: false, code: "413"))
    err = assert_raises(SmartPrompt::LLMAPIError) do
      with_http_new(fake) { @client.http_post_multipart("https://h/p", {}, "file", tmp.path, "text/plain") }
    end
    assert_match(/Test multipart API error/, err.message)
  ensure
    tmp&.unlink
  end

  # ---- stream_chat ----------------------------------------------------------

  def test_stream_chat_yields_each_parsed_payload_until_done
    resp = FakeStreamResponse.new([
      "data: {\"choices\":[{\"delta\":{\"content\":\"hi\"}}]}\n",
      "data: [DONE]\n",
    ])
    collected = []
    with_http_new(FakeStreamHTTP.new(resp)) do
      @client.stream_chat("https://h/p", {}) { |d| collected << d }
    end
    assert_equal([{ "choices" => [{ "delta" => { "content" => "hi" } }] }], collected)
  end

  def test_stream_chat_skips_unparseable_lines
    resp = FakeStreamResponse.new(["data: not-json\n", "data: {\"ok\":1}\n"])
    collected = []
    with_http_new(FakeStreamHTTP.new(resp)) do
      @client.stream_chat("https://h/p", {}) { |d| collected << d }
    end
    assert_equal([{ "ok" => 1 }], collected)
  end

  def test_stream_chat_splits_multiple_events_in_one_segment
    resp = FakeStreamResponse.new(["data: {\"a\":1}\ndata: {\"b\":2}\n"])
    collected = []
    with_http_new(FakeStreamHTTP.new(resp)) do
      @client.stream_chat("https://h/p", {}) { |d| collected << d }
    end
    assert_equal([{ "a" => 1 }, { "b" => 2 }], collected)
  end

  def test_stream_chat_non_2xx_raises_stream_message
    resp = FakeStreamResponse.new([], success: false)
    err = assert_raises(SmartPrompt::LLMAPIError) do
      with_http_new(FakeStreamHTTP.new(resp)) do
        @client.stream_chat("https://h/p", {}) { |_| }
      end
    end
    assert_match(/Test stream error: 500 - err-body/, err.message)
  end
end
