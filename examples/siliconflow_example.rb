# 硅基流动 (SiliconFlow / SiliconCloud) Example for SmartPrompt
#
# Demonstrates every SiliconFlow model category through one SiliconFlowAdapter:
#   1. 文本对话 (chat) — sync + streaming
#   2. 多模态 (vision)
#   3. 向量模型 (embeddings)
#   4. 重排 (rerank)
#   5. 文生图 (image)
#   6. 文生视频 (async submit -> poll -> download)
#   7. 语音合成 (TTS)
#   8. 语音识别 (ASR)
#
# Requires a valid SiliconFlow API key in SILICONFLOW_API_KEY
# (https://cloud.siliconflow.cn/). Defaults use free-tier models so it works
# out-of-box once the key is set.

require_relative "../lib/smart_prompt"

api_key = ENV["SILICONFLOW_API_KEY"]
base = "https://api.siliconflow.cn/v1"

config = {
  "adapters" => { "siliconflow" => "SiliconFlowAdapter" },
  "llms" => {
    "sf_chat"   => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "Qwen/Qwen2.5-7B-Instruct" },
    "sf_vision" => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "Qwen/Qwen2.5-VL-72B-Instruct" },
    "sf_embed"  => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "BAAI/bge-m3" },
    "sf_rerank" => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "BAAI/bge-reranker-v2-m3" },
    "sf_image"  => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "Kwai-Kolors/Kolors" },
    "sf_video"  => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "Wan-AI/Wan2.2-T2V-A14B" },
    "sf_tts"    => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "FunAudioLLM/CosyVoice2-0.5B" },
    "sf_asr"    => { "adapter" => "siliconflow", "url" => base, "api_key" => api_key, "model" => "FunAudioLLM/SenseVoiceSmall" },
  },
  "default_llm" => "sf_chat",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log",
}

File.write("siliconflow_config.yml", config.to_yaml)
engine = SmartPrompt::Engine.new("siliconflow_config.yml")

puts "=== SmartPrompt 硅基流动 SiliconFlow Demo ==="
unless api_key
  puts "Note: SILICONFLOW_API_KEY is not set — the API calls below will fail at the network layer."
end

# 1. Chat (sync)
puts "\n=== Example 1: 文本对话 (sync) ==="
begin
  result = engine.call_worker(:siliconflow_chat, { prompt: "用一句话介绍硅基流动 SiliconFlow。" })
  puts "Reply: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 2. Chat (streaming)
puts "\n=== Example 2: 文本对话 (streaming) ==="
begin
  engine.call_worker_by_stream(:siliconflow_chat, { prompt: "写两句关于春天的诗。" }) do |chunk, _|
    print chunk.dig("choices", 0, "delta", "content").to_s
  end
  puts
rescue => e
  puts "Error: #{e.message}"
end

# 3. Multimodal vision
puts "\n=== Example 3: 多模态 ==="
begin
  result = engine.call_worker(:siliconflow_vision, {
    image_url: "https://img1.baidu.com/it/u=1966616150,2146512490&fm=253&fmt=auto&app=138&f=JPEG?w=500&h=282",
    question: "图片里有什么？",
  })
  puts "Vision result: #{result}"
rescue => e
  puts "Error: #{e.message}"
end

# 4. Embeddings (BAAI/bge-m3)
puts "\n=== Example 4: 向量模型 ==="
begin
  vector = engine.call_worker(:siliconflow_embed, { text: "硅基流动大模型", length: 1024 })
  puts "Embedding dim: #{vector.is_a?(Array) ? vector.size : vector} (first 5: #{vector.first(5) rescue vector})"
rescue => e
  puts "Error: #{e.message}"
end

# 5. Rerank — reorder documents by relevance to a query.
puts "\n=== Example 5: 重排 (rerank) ==="
begin
  result = engine.call_worker(:siliconflow_rerank, {
    query: "如何用 Python 读取文件？",
    documents: [
      "在 Python 中可以用 open() 函数打开文件并读取内容。",
      "JavaScript 是一种运行在浏览器中的脚本语言。",
      "使用 with open(path) as f 可以安全地读取文件。",
    ],
    top_n: 2,
  })
  result.each { |r| puts "  idx=#{r[:index]} score=#{r[:relevance_score]}" }
rescue => e
  puts "Error: #{e.message}"
end

# 6. Text-to-image (Kolors)
puts "\n=== Example 6: 文生图 ==="
begin
  result = engine.call_worker(:siliconflow_image, {
    prompt: "一只在书房里读书的猫，水墨画风格",
    image_size: "1024x1024",
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "siliconflow_cat",
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

# 7. Text-to-video (Wan2.2, async) — may take a couple of minutes.
puts "\n=== Example 7: 文生视频 (async) ==="
begin
  result = engine.call_worker(:siliconflow_video, {
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
    puts "Submitted request: #{result[:submitted]}"
  end
rescue => e
  puts "Error: #{e.message}"
end

# 8. TTS (CosyVoice2)
puts "\n=== Example 8: 语音合成 (TTS) ==="
begin
  info = engine.call_worker(:siliconflow_tts, {
    text: "你好，这是硅基流动语音合成的测试。",
    voice: "FunAudioLLM/CosyVoice2-0.5B:alex",
    output_path: "./generated_audio/siliconflow_tts.mp3",
  })
  puts "Audio saved: #{info[:file_path]}"
rescue => e
  puts "Error: #{e.message}"
end

# 9. ASR (SenseVoiceSmall) — needs a real audio file path.
puts "\n=== Example 9: 语音识别 (ASR) ==="
audio = ENV["SILICONFLOW_ASR_SAMPLE"] || "./generated_audio/siliconflow_tts.mp3"
if File.exist?(audio)
  begin
    result = engine.call_worker(:siliconflow_asr, { audio_file: audio })
    puts "Transcription: #{result[:text]}"
  rescue => e
    puts "Error: #{e.message}"
  end
else
  puts "Skipped: set SILICONFLOW_ASR_SAMPLE to an audio file path (or run TTS first) to test ASR."
end

puts "\n=== All examples completed ==="

File.delete("siliconflow_config.yml") if File.exist?("siliconflow_config.yml")
