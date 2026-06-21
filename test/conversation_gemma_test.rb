# frozen_string_literal: true

require "minitest/autorun"
require "tempfile"
require "smart_prompt"

class ConversationGemmaTest < Minitest::Test
  class FakeEngine
    attr_reader :adapters, :llms, :models, :templates, :current_adapter, :history_messages

    def initialize(adapter)
      @adapters = {}
      @llms = { "gemma" => adapter }
      @models = { "gemma4/12b" => { "use" => "gemma", "model" => "gemma-4-12B-it" } }
      @templates = {}
      @current_adapter = nil
      @history_messages = []
    end
  end

  class CapturingAdapter
    attr_reader :messages, :request_options

    def send_request(messages, _model = nil, _temperature = 0.7, _tools = nil, _proc = nil, request_options = {})
      @messages = messages
      @request_options = request_options
      "ok"
    end
  end

  def setup
    @adapter = CapturingAdapter.new
    @engine = FakeEngine.new(@adapter)
  end

  def test_multimodal_prompt_orders_image_text_audio_for_gemma
    conversation = SmartPrompt::Conversation.new(@engine)

    # media_part base64-encodes real local files (file_upload fix); use temp files.
    png = Tempfile.new(["chart", ".png"]); png.binmode; png.write("fake-png"); png.close
    wav = Tempfile.new(["audio", ".wav"]); wav.binmode; wav.write("fake-wav"); wav.close

    conversation.use_model("gemma4/12b")
    conversation.image(png.path, token_budget: 560)
    conversation.audio(wav.path)
    conversation.prompt("Summarize the image and audio.")
    conversation.send_msg

    content = @adapter.messages.last[:content]
    assert_equal ["image_url", "text", "input_audio"], content.map { |part| part["type"] }
    assert_equal 560, content.first["token_budget"]
    assert_equal "Summarize the image and audio.", content[1]["text"]
  ensure
    png&.unlink
    wav&.unlink
  end

  def test_thinking_prepends_gemma_control_token_to_system_prompt
    conversation = SmartPrompt::Conversation.new(@engine)

    conversation.thinking
    conversation.sys_msg("Think carefully.", { with_history: false })

    assert_equal "<|think|>\nThink carefully.", conversation.messages.first[:content]
  end

  def test_request_options_are_passed_to_six_argument_adapters
    conversation = SmartPrompt::Conversation.new(@engine)

    conversation.use("gemma")
    conversation.request_options(response_format: { type: "json_object" })
    conversation.prompt("Return JSON.")
    conversation.send_msg

    assert_equal({ response_format: { type: "json_object" } }, @adapter.request_options)
  end
end
