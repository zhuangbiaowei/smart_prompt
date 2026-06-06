# frozen_string_literal: true

require "minitest/autorun"
require "smart_prompt"

class OpenAIAdapterTest < Minitest::Test
  class FakeClient
    attr_reader :parameters

    def chat(parameters:)
      @parameters = parameters
      {
        "choices" => [
          {
            "message" => {
              "content" => "ok",
            },
          },
        ],
      }
    end
  end

  def test_send_request_passes_configured_generation_parameters
    client = FakeClient.new
    adapter = SmartPrompt::OpenAIAdapter.allocate
    adapter.instance_variable_set(:@client, client)
    adapter.instance_variable_set(:@config, {
      "model" => "gemma-4-12B-it",
      "top_p" => 0.95,
      "top_k" => 64,
      "max_tokens" => 512,
    })

    result = adapter.send_request([{ role: "user", content: "hello" }])

    assert_equal "ok", result
    assert_equal "gemma-4-12B-it", client.parameters[:model]
    assert_equal 0.95, client.parameters[:top_p]
    assert_equal 64, client.parameters[:top_k]
    assert_equal 512, client.parameters[:max_tokens]
  end

  def test_send_request_allows_worker_request_options_to_override_config
    client = FakeClient.new
    adapter = SmartPrompt::OpenAIAdapter.allocate
    adapter.instance_variable_set(:@client, client)
    adapter.instance_variable_set(:@config, {
      "model" => "gemma-4-12B-it",
      "top_p" => 0.95,
    })

    adapter.send_request(
      [{ role: "user", content: "hello" }],
      nil,
      0.7,
      nil,
      nil,
      top_p: 0.8,
      response_format: { type: "json_object" },
    )

    assert_equal 0.8, client.parameters[:top_p]
    assert_equal({ type: "json_object" }, client.parameters[:response_format])
  end
end
