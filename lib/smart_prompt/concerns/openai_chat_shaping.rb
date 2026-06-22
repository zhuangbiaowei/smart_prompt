module SmartPrompt
  # Shared shaping of Net::HTTP chat responses into the OpenAI completion / stream
  # shape that the rest of SmartPrompt (Engine#@stream_proc, Conversation) expects.
  #
  # Reasoning models expose a thinking trace under a provider-specific field —
  # surfaced here uniformly as `reasoning_content`. Adapters override one hook:
  #
  #   reasoning_field_name  — the source field on message/delta (default
  #     "reasoning_content"; SenseNova uses "reasoning"). Its value is remapped to
  #     reasoning_content so Engine#@stream_proc needs no per-provider logic.
  #
  #   extra_top_level_fields(raw) — extra top-level keys to copy onto the shaped
  #     response/chunk (default {}; SenseNova adds system_fingerprint).
  module OpenAIChatShaping
    def build_completion_response(raw)
      msg = raw.dig("choices", 0, "message") || {}
      message = { "role" => msg["role"] || "assistant" }
      message["content"] = msg["content"]
      reasoning = msg[reasoning_field_name]
      message["reasoning_content"] = reasoning if reasoning
      message["tool_calls"] = msg["tool_calls"] if msg["tool_calls"]

      response = {
        "id"      => raw["id"],
        "object"  => raw["object"] || "chat.completion",
        "created" => raw["created"],
        "model"   => raw["model"],
        "choices" => [{
          "index"         => 0,
          "message"       => message,
          "finish_reason" => raw.dig("choices", 0, "finish_reason"),
        }],
      }
      response["usage"] = raw["usage"] if raw["usage"]
      merge_extra_top_level(response, raw)
      response
    end

    def build_stream_chunk(data)
      chunk = {
        "id"      => data["id"],
        "object"  => data["object"],
        "created" => data["created"],
        "model"   => data["model"],
      }
      chunk["usage"] = data["usage"] if data["usage"]
      merge_extra_top_level(chunk, data)

      choices = data["choices"] || []
      if choices.any?
        delta = choices[0]["delta"] || {}
        new_delta = {}
        new_delta["role"]              = delta["role"]        if delta["role"]
        new_delta["content"]           = delta["content"]     if delta["content"]
        reasoning = delta[reasoning_field_name]
        new_delta["reasoning_content"] = reasoning if reasoning
        new_delta["tool_calls"]        = delta["tool_calls"]  if delta["tool_calls"]
        chunk["choices"] = [{
          "index"         => choices[0]["index"] || 0,
          "delta"         => new_delta,
          "finish_reason" => choices[0]["finish_reason"],
        }]
      else
        chunk["choices"] = []
      end
      chunk
    end

    # ---- hooks (override in adapter) -----------------------------------------

    def reasoning_field_name
      "reasoning_content"
    end

    def extra_top_level_fields(_raw)
      {}
    end

    private

    def merge_extra_top_level(target, raw)
      extra_top_level_fields(raw).each do |k, v|
        target[k] = v unless v.nil? || target.key?(k)
      end
    end
  end
end
