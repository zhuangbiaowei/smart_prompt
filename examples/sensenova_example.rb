# SenseNova (商汤 日日新) Example for SmartPrompt
#
# Demonstrates all four SenseNova model categories through one SenseNovaAdapter:
#   1. 商量 文本对话  (chat)        — sync + streaming
#   2. 商量 图文多模态 (vision)
#   3. Cupido 向量模型 (embeddings)
#   4. 秒画 文生图    (text-to-image)
#
# Requires a valid SenseNova API key in the SENSENOVA_API_KEY environment variable
# (get one at https://platform.sensenova.cn/console) and the relevant models enabled.

require_relative "../lib/smart_prompt"

api_key = ENV["SENSENOVA_API_KEY"]

config = {
  "adapters" => {
    "sensenova" => "SenseNovaAdapter",
  },
  "llms" => {
    "sensechat" => {
      "adapter" => "sensenova",
      "url" => "https://token.sensenova.cn/v1",
      "api_key" => api_key,
      "model" => "sensenova-6.7-flash-lite",
      "temperature" => 0.7,
    },
    "sensevision" => {
      "adapter" => "sensenova",
      "url" => "https://token.sensenova.cn/v1",
      "api_key" => api_key,
      "model" => "sensenova-6.7-flash-lite",
    },
    "senseembedding" => {
      "adapter" => "sensenova",
      "url" => "https://api.sensenova.cn/compatible-mode/v2",
      "embeddings_url" => "https://api.sensenova.cn/v1/llm/embeddings",
      "api_key" => api_key,
      "model" => "Cupido",
    },
    "senseimage" => {
      "adapter" => "sensenova",
      "url" => "https://token.sensenova.cn/v1",
      "image_url" => "https://token.sensenova.cn/v1/images/generations",
      "api_key" => api_key,
      "model" => "sensenova-u1-fast",
    },
  },
  "default_llm" => "sensechat",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log",
}

File.write("sensenova_config.yml", config.to_yaml)
engine = SmartPrompt::Engine.new("sensenova_config.yml")

puts "=== SmartPrompt SenseNova Demo ==="
unless api_key
  puts "Note: SENSENOVA_API_KEY is not set — the API calls below will fail at the network layer."
end

# 1. Chat (sync)
puts "\n=== Example 1: 商量 文本对话 (sync) ==="
begin
  result = engine.call_worker(:sensenova_chat, { prompt: "用一句话介绍商汤日日新大模型。" })
  puts "Reply: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 2. Chat (streaming) — tokens are printed as they arrive.
puts "\n=== Example 2: 商量 文本对话 (streaming) ==="
begin
  engine.call_worker_by_stream(:sensenova_chat, { prompt: "写两句关于春天的诗。" }) do |chunk, _|
    if (delta = chunk.dig("choices", 0, "delta", "content"))
      print delta
    end
  end
  puts
rescue => e
  puts "Error: #{e.message}"
end

# 3. Multimodal vision
puts "\n=== Example 3: 商量 图文多模态 ==="
begin
  result = engine.call_worker(:sensenova_vision, {
    image_url: "https://img0.baidu.com/it/u=3775751201,1094020238&fm=253&fmt=auto&app=138&f=JPEG?w=500&h=615",
    question: "图片里有什么？",
  })
  puts "Vision result: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 4. Embeddings (Cupido)
puts "\n=== Example 4: Cupido 向量模型 ==="
begin
  vector = engine.call_worker(:sensenova_embed, { text: "商汤日日新大模型", length: 1024 })
  puts "Embedding dim: #{vector.is_a?(Array) ? vector.size : vector} (first 5: #{vector.first(5) rescue vector})"
rescue => e
  puts "Error: #{e.message}"
end

# 5. Text-to-image (秒画)
puts "\n=== Example 5: 秒画 文生图 ==="
begin
  result = engine.call_worker(:sensenova_image, {
    prompt: "一只在书房里读书的可爱机器人，温暖的光线，数字插画",
    size: "2048x2048",
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "sensenova_robot",
  })
  if result.is_a?(Hash) && result[:images]
    puts "Generated #{result[:images].size} image(s)"
    puts "First image URL: #{result[:images].first[:url]}"
    puts "Saved files: #{result[:saved_files]}"
  else
    puts "Result: #{result}"
  end
rescue => e
  puts "Error (image endpoint may need a live key to confirm): #{e.message}"
end

puts "\n=== All examples completed ==="

File.delete("sensenova_config.yml") if File.exist?("sensenova_config.yml")
