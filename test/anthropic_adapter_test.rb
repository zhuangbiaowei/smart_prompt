# frozen_string_literal: true

require "minitest/autorun"
require "smart_prompt"

class AnthropicAdapterTest < Minitest::Test
  def setup
    @adapter = SmartPrompt::AnthropicAdapter.allocate
  end

  def test_extract_content_returns_string_for_text_only_response
    response = {
      "content" => [
        { "type" => "text", "text" => "Hello" },
        { "type" => "text", "text" => " world" },
      ],
    }

    assert_equal "Hello world", @adapter.send(:extract_content, response)
  end

  def test_extract_content_preserves_tool_use_as_openai_compatible_tool_calls
    response = {
      "id" => "msg_123",
      "model" => "claude-3-5-sonnet-latest",
      "stop_reason" => "tool_use",
      "usage" => { "input_tokens" => 10, "output_tokens" => 20 },
      "content" => [
        { "type" => "text", "text" => "I will check that." },
        {
          "type" => "tool_use",
          "id" => "toolu_123",
          "name" => "lookup",
          "input" => { "query" => "weather" },
        },
      ],
    }

    result = @adapter.send(:extract_content, response)
    message = result.dig("choices", 0, "message")
    tool_call = message.fetch("tool_calls").first

    assert_equal "chat.completion", result["object"]
    assert_equal "assistant", message["role"]
    assert_equal "I will check that.", message["content"]
    assert_equal "tool_calls", result.dig("choices", 0, "finish_reason")
    assert_equal "toolu_123", tool_call["id"]
    assert_equal "function", tool_call["type"]
    assert_equal "lookup", tool_call.dig("function", "name")
    assert_equal({ "query" => "weather" }, JSON.parse(tool_call.dig("function", "arguments")))
  end
end
