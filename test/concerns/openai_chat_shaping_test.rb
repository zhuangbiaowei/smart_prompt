require 'minitest/autorun'
require 'json'
require './lib/smart_prompt'

# Direct tests for the OpenAIChatShaping concern. Focuses on branches the adapter
# tests miss: tool_calls passthrough, the negative reasoning case, the object
# default, and the extra_top_level_fields / reasoning_field_name hooks.
class OpenAIChatShapingConcernTest < Minitest::Test
  class Holder
    include SmartPrompt::OpenAIChatShaping
  end

  # Override extra_top_level_fields to surface system_fingerprint (the SenseNova case).
  class FingerprintHolder < Holder
    def extra_top_level_fields(raw)
      { "system_fingerprint" => raw["system_fingerprint"] }
    end
  end

  # Override reasoning_field_name (the SenseNova case: source field is "reasoning").
  class ReasoningHolder < Holder
    def reasoning_field_name
      "reasoning"
    end
  end

  def setup
    @s = Holder.new
  end

  # ---- build_completion_response --------------------------------------------

  def test_completion_basic_content_and_object_default
    raw = { "id" => "a", "choices" => [{ "index" => 0, "message" => { "role" => "assistant", "content" => "hi" }, "finish_reason" => "stop" }] }
    resp = @s.build_completion_response(raw)
    assert_equal "hi", resp.dig("choices", 0, "message", "content")
    assert_equal "chat.completion", resp["object"] # default when raw omits it
    refute resp.dig("choices", 0, "message").key?("reasoning_content") # no reasoning field
  end

  def test_completion_surfaces_reasoning_content
    raw = { "choices" => [{ "message" => { "role" => "assistant", "content" => "hi", "reasoning_content" => "think" }, "finish_reason" => "stop" }] }
    assert_equal "think", @s.build_completion_response(raw).dig("choices", 0, "message", "reasoning_content")
  end

  def test_completion_passes_through_tool_calls
    raw = { "choices" => [{ "message" => { "role" => "assistant", "content" => nil, "tool_calls" => [{ "id" => "1", "function" => {} }] }, "finish_reason" => "tool_calls" }] }
    calls = @s.build_completion_response(raw).dig("choices", 0, "message", "tool_calls")
    assert_equal [{ "id" => "1", "function" => {} }], calls
  end

  def test_completion_forwards_usage
    raw = { "choices" => [{ "message" => { "content" => "hi" }, "finish_reason" => "stop" }], "usage" => { "total_tokens" => 9 } }
    assert_equal 9, @s.build_completion_response(raw).dig("usage", "total_tokens")
  end

  # ---- build_stream_chunk ---------------------------------------------------

  def test_stream_chunk_content_and_reasoning
    chunk = @s.build_stream_chunk(JSON.parse('{"id":"x","choices":[{"index":0,"delta":{"content":"a","reasoning_content":"b"},"finish_reason":""}]}'))
    assert_equal "a", chunk.dig("choices", 0, "delta", "content")
    assert_equal "b", chunk.dig("choices", 0, "delta", "reasoning_content")
  end

  def test_stream_chunk_passes_through_role_and_tool_calls
    chunk = @s.build_stream_chunk(JSON.parse('{"id":"x","choices":[{"index":0,"delta":{"role":"assistant","tool_calls":[{"index":0,"function":{"arguments":"{}"}}]},"finish_reason":""}]}'))
    assert_equal "assistant", chunk.dig("choices", 0, "delta", "role")
    assert_equal [{ "index" => 0, "function" => { "arguments" => "{}" } }], chunk.dig("choices", 0, "delta", "tool_calls")
  end

  def test_stream_chunk_empty_choices_passes_usage
    chunk = @s.build_stream_chunk({ "id" => "x", "choices" => [], "usage" => { "total_tokens" => 7 } })
    assert_equal [], chunk["choices"]
    assert_equal 7, chunk.dig("usage", "total_tokens")
  end

  # ---- extra_top_level_fields hook (SenseNova system_fingerprint) -----------

  def test_extra_fields_merged_into_completion
    raw = { "id" => "a", "system_fingerprint" => "fp1", "choices" => [{ "message" => { "content" => "hi" }, "finish_reason" => "stop" }] }
    assert_equal "fp1", FingerprintHolder.new.build_completion_response(raw)["system_fingerprint"]
  end

  def test_extra_fields_merged_into_stream_chunk
    chunk = FingerprintHolder.new.build_stream_chunk({ "id" => "x", "system_fingerprint" => "fp2", "choices" => [{ "delta" => { "content" => "a" }, "finish_reason" => "" }] })
    assert_equal "fp2", chunk["system_fingerprint"]
  end

  def test_extra_fields_skips_nil_and_does_not_clobber_existing
    # raw has no system_fingerprint -> hook returns nil -> key not added
    raw = { "id" => "a", "choices" => [{ "message" => { "content" => "hi" }, "finish_reason" => "stop" }] }
    refute FingerprintHolder.new.build_completion_response(raw).key?("system_fingerprint")
  end

  # ---- reasoning_field_name hook (SenseNova reasoning -> reasoning_content) -

  def test_reasoning_field_name_hook_remaps_source_field
    raw = { "choices" => [{ "message" => { "role" => "assistant", "content" => "hi", "reasoning" => "think" }, "finish_reason" => "stop" }] }
    assert_equal "think", ReasoningHolder.new.build_completion_response(raw).dig("choices", 0, "message", "reasoning_content")

    chunk = ReasoningHolder.new.build_stream_chunk(JSON.parse('{"id":"x","choices":[{"index":0,"delta":{"reasoning":"想"},"finish_reason":""}]}'))
    assert_equal "想", chunk.dig("choices", 0, "delta", "reasoning_content")
  end
end
