# TTS Example for SmartPrompt
# This example demonstrates how to use the new TTSAdapter

require_relative '../lib/smart_prompt'

# Configuration for TTS capabilities
config = {
  "adapters" => {
    "multimodal" => "MultimodalAdapter",
    "image_generation" => "ImageGenerationAdapter",
    "video_generation" => "VideoGenerationAdapter",
    "tts" => "TTSAdapter"
  },
  "llms" => {
    "qwen_vl" => {
      "adapter" => "multimodal",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => ENV["SILICONFLOW_API_KEY"],
      "model" => "Qwen/Qwen2.5-VL-7B-Instruct"
    },
    "image_gen" => {
      "adapter" => "image_generation",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => ENV["SILICONFLOW_API_KEY"],
      "model" => "stabilityai/stable-diffusion-xl-base-1.0"
    },
    "video_gen" => {
      "adapter" => "video_generation",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => ENV["SILICONFLOW_API_KEY"],
      "model" => "Wan-AI/Wan2.2-T2V-A14B"
    },
    "tts_service" => {
      "adapter" => "tts",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => ENV["SILICONFLOW_API_KEY"],
      "model" => "FunAudioLLM/CosyVoice2-0.5B"
    }
  },
  "default_llm" => "qwen_vl",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log"
}

# Write config to file
File.write('tts_config.yml', config.to_yaml)

# Initialize engine
engine = SmartPrompt::Engine.new('tts_config.yml')

puts "=== SmartPrompt TTS Demo ==="

# Example 1: Basic text-to-speech synthesis
puts "\n=== Example 1: Basic TTS Synthesis ==="
begin
  result = engine.call_worker(:tts_synthesizer, {
    text: "欢迎使用智能提示系统，这是一个文本转语音功能的演示。",
    voice: "alloy",
    speed: 1.0,
    response_format: "mp3",
    save_to_file: true,
    output_dir: "./generated_audio",
    filename_prefix: "basic_tts"
  })

  puts "TTS synthesis successful!"
  puts "Audio file: #{result[:audio_file][:file_path]}"
  puts "Text length: #{result[:audio_file][:text_length]} characters"
  puts "Voice: #{result[:audio_file][:voice]}"

rescue => e
  puts "Error in TTS synthesis: #{e.message}"
  puts "Note: This example requires a valid SILICONFLOW_API_KEY environment variable"
end

# Example 2: Multilingual TTS
puts "\n=== Example 2: Multilingual TTS ==="
begin
  # English text
  result_en = engine.call_worker(:multilingual_tts, {
    text: "Hello, this is a demonstration of text-to-speech functionality.",
    voice: "echo",
    save_to_file: true,
    output_dir: "./multilingual_audio",
    filename_prefix: "english_tts"
  })

  puts "English TTS successful!"
  puts "Detected language: #{result_en[:detected_language]}"
  puts "Audio file: #{result_en[:audio_file][:file_path]}"

  # Chinese text
  result_zh = engine.call_worker(:multilingual_tts, {
    text: "这是一个中文文本转语音的演示，支持多种语言。",
    voice: "nova",
    save_to_file: true,
    output_dir: "./multilingual_audio",
    filename_prefix: "chinese_tts"
  })

  puts "Chinese TTS successful!"
  puts "Detected language: #{result_zh[:detected_language]}"
  puts "Audio file: #{result_zh[:audio_file][:file_path]}"

rescue => e
  puts "Error in multilingual TTS: #{e.message}"
end

# Example 3: Voice selection demo
puts "\n=== Example 3: Voice Selection Demo ==="
begin
  result = engine.call_worker(:voice_selector, {
    text: "这是一个不同音色的演示，您可以听到不同声音的朗读效果。",
    save_to_file: true,
    output_dir: "./voice_demos"
  })

  puts "Voice selection demo successful!"
  puts "Available voices: #{result[:available_voices].keys.join(', ')}"
  puts "Selected voice: #{result[:selected_voice]}"
  puts "Audio file: #{result[:audio_file][:file_path]}"

rescue => e
  puts "Error in voice selection: #{e.message}"
end

# Example 4: Speed variation demo
puts "\n=== Example 4: Speed Variation Demo ==="
begin
  result = engine.call_worker(:speed_variation_tts, {
    text: "这是一个语速变化的演示，您可以听到不同语速的朗读效果。",
    voice: "alloy",
    speeds: [0.5, 0.75, 1.0, 1.5, 2.0],
    save_to_file: true,
    output_dir: "./speed_variations"
  })

  puts "Speed variation demo successful!"
  puts "Generated #{result[:speed_variations].size} audio files at different speeds"
  result[:speed_variations].each do |variation|
    puts "  - Speed #{variation[:speed]}: #{variation[:audio_file][:file_path]}"
  end

rescue => e
  puts "Error in speed variation: #{e.message}"
end

# Example 5: Custom voice management
puts "\n=== Example 5: Custom Voice Management ==="
begin
  # List available voices
  result = engine.call_worker(:custom_voice_manager, {
    action: "list"
  })

  puts "Voice management demo successful!"
  puts "Predefined voices: #{result[:predefined_voices].keys.join(', ')}"
  puts "Custom voices: #{result[:custom_voices].size}"

  # Note: Creating custom voices requires reference audio files
  # Uncomment the following lines if you have reference audio files:
  #
  # result = engine.call_worker(:custom_voice_manager, {
  #   action: "create",
  #   name: "my_custom_voice",
  #   reference_audio_file: "./reference_audio.wav",
  #   description: "My custom voice created from reference audio"
  # })
  #
  # puts "Custom voice created: #{result[:voice_data][:voice_id]}"

rescue => e
  puts "Error in voice management: #{e.message}"
end

# Example 6: Batch TTS processing
puts "\n=== Example 6: Batch TTS Processing ==="
begin
  result = engine.call_worker(:batch_tts, {
    texts: [
      "这是第一条文本内容。",
      "这是第二条文本内容，用于批量处理演示。",
      "这是第三条文本内容，展示批量文本转语音功能。"
    ],
    voice: "alloy",
    save_to_file: true,
    output_dir: "./batch_audio"
  })

  puts "Batch TTS processing successful!"
  puts "Generated #{result[:batch_results].size} audio files"
  result[:batch_results].each do |batch_result|
    puts "  - Text #{batch_result[:index] + 1}: #{batch_result[:audio_file][:file_path]}"
  end

rescue => e
  puts "Error in batch TTS: #{e.message}"
end

# Example 7: Direct adapter usage
puts "\n=== Example 7: Direct Adapter Usage ==="
begin
  # Get the adapter directly
  adapter = engine.llms["tts_service"]

  # Synthesize speech directly
  audio_data = adapter.synthesize_speech(
    "这是直接使用适配器的演示，不通过Worker。",
    voice: "echo",
    speed: 1.2,
    response_format: "mp3"
  )

  puts "Direct adapter usage successful!"
  puts "Generated audio data with format: #{audio_data[:format]}"
  puts "Text length: #{audio_data[:text_length]} characters"

  # Save to file
  output_path = "./direct_audio/direct_tts_#{Time.now.to_i}.mp3"
  result = adapter.synthesize_to_file(
    "这是直接保存到文件的演示。",
    output_path,
    voice: "nova",
    speed: 1.0
  )

  puts "Direct file synthesis successful!"
  puts "Audio file: #{result[:file_path]}"

rescue => e
  puts "Error in direct adapter usage: #{e.message}"
end

puts "\n=== All examples completed ==="
puts "\nImportant Notes:"
puts "1. TTS requires valid SILICONFLOW_API_KEY environment variable"
puts "2. Audio files are saved in various formats (mp3, wav, etc.)"
puts "3. Custom voice creation requires reference audio files"
puts "4. Multiple languages are supported (Chinese, English, Japanese, Korean)"
puts "5. Speed can be adjusted from 0.25x to 4.0x"

# Clean up
File.delete('tts_config.yml') if File.exist?('tts_config.yml')