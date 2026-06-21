# 智谱 AI (BigModel / GLM) Example for SmartPrompt
#
# Demonstrates every Zhipu model category through one ZhipuAIAdapter:
#   1. 文本对话 (chat) — sync + streaming
#   2. 图文多模态 (vision)
#   3. 向量模型 (embeddings)
#   4. 文生图 (CogView)
#   5. 文生视频 (CogVideoX, async submit -> poll -> download)
#   6. 语音合成 (GLM-TTS)
#   7. 语音识别 (GLM-ASR-2512)
#
# Requires a valid Zhipu API key in ZHIPUAI_API_KEY (https://open.bigmodel.cn/).
# Defaults use free-tier models so it works out-of-box once the key is set.

require_relative "../lib/smart_prompt"

api_key = ENV["ZHIPUAI_API_KEY"]
base = "https://open.bigmodel.cn/api/paas/v4"

config = {
  "adapters" => { "zhipu" => "ZhipuAIAdapter" },
  "llms" => {
    "glm"        => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "glm-4-flash" },
    "glm_vision" => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "glm-4v-flash" },
    "embedding"  => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "embedding-3", "dimensions" => 1024 },
    "cogview"    => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "cogview-3-flash" },
    "cogvideo"   => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "cogvideox-flash" },
    "glm_tts"    => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "glm-tts" },
    "glm_asr"    => { "adapter" => "zhipu", "url" => base, "api_key" => api_key, "model" => "glm-asr-2512" },
  },
  "default_llm" => "glm",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log",
}

File.write("zhipu_config.yml", config.to_yaml)
engine = SmartPrompt::Engine.new("zhipu_config.yml")

puts "=== SmartPrompt 智谱 GLM Demo ==="
unless api_key
  puts "Note: ZHIPUAI_API_KEY is not set — the API calls below will fail at the network layer."
end

# 1. Chat (sync)
puts "\n=== Example 1: 文本对话 (sync) ==="
begin
  result = engine.call_worker(:glm_chat, { prompt: "用一句话介绍智谱GLM。" })
  puts "Reply: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 2. Chat (streaming)
puts "\n=== Example 2: 文本对话 (streaming) ==="
begin
  engine.call_worker_by_stream(:glm_chat, { prompt: "写两句关于春天的诗。" }) do |chunk, _|
    print chunk.dig("choices", 0, "delta", "content").to_s
  end
  puts
rescue => e
  puts "Error: #{e.message}"
end

# 3. Multimodal vision
puts "\n=== Example 3: 图文多模态 ==="
begin
  result = engine.call_worker(:glm_vision, {
    image_url: "https://img1.baidu.com/it/u=1966616150,2146512490&fm=253&fmt=auto&app=138&f=JPEG?w=500&h=282",
    question: "图片里有什么？",
  })
  puts "Vision result: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 4. Embeddings (embedding-3)
puts "\n=== Example 4: 向量模型 ==="
begin
  vector = engine.call_worker(:glm_embed, { text: "智谱GLM大模型", length: 1024 })
  puts "Embedding dim: #{vector.is_a?(Array) ? vector.size : vector} (first 5: #{vector.first(5) rescue vector})"
rescue => e
  puts "Error: #{e.message}"
end

# 5. Text-to-image (CogView)
puts "\n=== Example 5: 文生图 ==="
begin
  result = engine.call_worker(:cogview_image, {
    prompt: "一只在书房里读书的猫，水墨画风格",
    size: "1024x1024",
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "zhipu_cat",
  })
  if result.is_a?(Hash) && result[:images]
    puts "Generated #{result[:images].size} image(s); first URL: #{result[:images].first[:url]}"
    puts "Saved files: #{result[:saved_files]}"
  else
    puts "Result: #{result}"
  end
rescue => e
  puts "Error: #{e.message}"
end

# 6. Text-to-video (CogVideoX, async) — may take a minute or two.
puts "\n=== Example 6: 文生视频 (async) ==="
begin
  result = engine.call_worker(:cogvideo_video, {
    prompt: "一只猫在阳光下打盹",
    wait_for_completion: true,
    download_to_file: true,
    output_dir: "./generated_videos",
    timeout: 600,
  })
  if result[:video]
    puts "Video ready: #{result[:video][:video_url]}"
    puts "Downloaded: #{result[:downloaded_file]}" if result[:downloaded_file]
  else
    puts "Submitted task: #{result[:submitted]}"
  end
rescue => e
  puts "Error: #{e.message}"
end

# 7. TTS (GLM-TTS)
puts "\n=== Example 7: 语音合成 (TTS) ==="
begin
  info = engine.call_worker(:glm_tts, { text: "你好，这是智谱语音合成的测试。", output_path: "./generated_audio/zhipu_tts.wav" })
  puts "Audio saved: #{info[:file_path]}"
rescue => e
  puts "Error: #{e.message}"
end

# 8. ASR (GLM-ASR-2512) — needs a real audio file path.
puts "\n=== Example 8: 语音识别 (ASR) ==="
audio = ENV["ZHIPU_ASR_SAMPLE"] || "./generated_audio/zhipu_tts.wav"
if File.exist?(audio)
  begin
    result = engine.call_worker(:glm_asr, { audio_file: audio })
    puts "Transcription: #{result[:text]}"
  rescue => e
    puts "Error: #{e.message}"
  end
else
  puts "Skipped: set ZHIPU_ASR_SAMPLE to an audio file path (or run TTS first) to test ASR."
end

puts "\n=== All examples completed ==="

File.delete("zhipu_config.yml") if File.exist?("zhipu_config.yml")
