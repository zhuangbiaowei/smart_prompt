# STT Example for SmartPrompt
# This example demonstrates how to use the new STTAdapter

require_relative '../lib/smart_prompt'

# Configuration for STT capabilities
config = {
  "adapters" => {
    "multimodal" => "MultimodalAdapter",
    "image_generation" => "ImageGenerationAdapter",
    "video_generation" => "VideoGenerationAdapter",
    "tts" => "TTSAdapter",
    "stt" => "STTAdapter"
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
    },
    "stt_service" => {
      "adapter" => "stt",
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
File.write('stt_config.yml', config.to_yaml)

# Initialize engine
engine = SmartPrompt::Engine.new('stt_config.yml')

puts "=== SmartPrompt STT Demo ==="

# Example 1: Basic speech-to-text transcription
puts "\n=== Example 1: Basic STT Transcription ==="
begin
  # Note: This example requires an actual audio file
  # Replace with a real audio file path for testing
  audio_file_path = "./test_audio.wav"

  if File.exist?(audio_file_path)
    result = engine.call_worker(:stt_transcriber, {
      audio_file: audio_file_path,
      language: "zh",
      response_format: "json"
    })

    puts "STT transcription successful!"
    puts "Transcribed text: #{result[:transcription][:text]}"
    puts "Language: #{result[:transcription][:language]}"
    puts "Duration: #{result[:transcription][:duration]} seconds"
    puts "File size: #{result[:transcription][:file_size]} bytes"
  else
    puts "Audio file not found: #{audio_file_path}"
    puts "Please create a test audio file to run this example"
  end

rescue => e
  puts "Error in STT transcription: #{e.message}"
  puts "Note: This example requires a valid SILICONFLOW_API_KEY environment variable"
end

# Example 2: URL-based transcription
puts "\n=== Example 2: URL-based STT Transcription ==="
begin
  # Note: Replace with a real audio URL for testing
  audio_url = "https://example.com/audio.wav"

  result = engine.call_worker(:stt_url_transcriber, {
    audio_url: audio_url,
    language: "en",
    response_format: "text"
  })

  puts "URL-based STT transcription successful!"
  puts "Transcribed text: #{result[:transcription][:text]}"
  puts "Audio URL: #{result[:transcription][:audio_url]}"

rescue => e
  puts "Error in URL-based STT: #{e.message}"
  puts "Note: This requires a valid audio URL"
end

# Example 3: Batch transcription
puts "\n=== Example 3: Batch STT Processing ==="
begin
  # Note: Replace with real audio files for testing
  audio_files = ["./audio1.wav", "./audio2.wav", "./audio3.wav"]
  existing_files = audio_files.select { |f| File.exist?(f) }

  if existing_files.any?
    result = engine.call_worker(:batch_stt, {
      audio_files: existing_files,
      language: "zh"
    })

    puts "Batch STT processing successful!"
    puts "Total files: #{result[:batch_result][:total_files]}"
    puts "Successful: #{result[:batch_result][:successful]}"
    puts "Failed: #{result[:batch_result][:failed]}"

    result[:batch_result][:results].each do |file_result|
      if file_result[:success]
        puts "  - #{File.basename(file_result[:file])}: #{file_result[:transcription][:text].length} characters"
      else
        puts "  - #{File.basename(file_result[:file])}: ERROR - #{file_result[:error]}"
      end
    end
  else
    puts "No audio files found for batch processing"
    puts "Please create test audio files to run this example"
  end

rescue => e
  puts "Error in batch STT: #{e.message}"
end

# Example 4: Audio file information
puts "\n=== Example 4: Audio File Information ==="
begin
  audio_file_path = "./test_audio.wav"

  if File.exist?(audio_file_path)
    result = engine.call_worker(:audio_info, {
      audio_file: audio_file_path
    })

    puts "Audio file information retrieved!"
    puts "File name: #{result[:audio_info][:file_name]}"
    puts "File size: #{result[:audio_info][:file_size]} bytes"
    puts "Format: #{result[:audio_info][:format]}"
    puts "Estimated duration: #{result[:audio_info][:estimated_duration]} seconds"
    puts "Supported: #{result[:audio_info][:supported]}"
  else
    puts "Audio file not found: #{audio_file_path}"
  end

rescue => e
  puts "Error getting audio info: #{e.message}"
end

# Example 5: Language detection
puts "\n=== Example 5: Language Detection ==="
begin
  # Test with Chinese text
  result = engine.call_worker(:language_detector, {
    text: "这是一个中文文本，用于语言检测演示。"
  })

  puts "Language detection successful!"
  puts "Text: #{result[:text]}"
  puts "Detected language: #{result[:detected_language]}"

  # Test with English text
  result_en = engine.call_worker(:language_detector, {
    text: "This is an English text for language detection demonstration."
  })

  puts "English text detected as: #{result_en[:detected_language]}"

rescue => e
  puts "Error in language detection: #{e.message}"
end

# Example 6: Multi-language STT
puts "\n=== Example 6: Multi-language STT ==="
begin
  audio_file_path = "./test_audio.wav"

  if File.exist?(audio_file_path)
    result = engine.call_worker(:multilingual_stt, {
      audio_file: audio_file_path
    })

    puts "Multi-language STT successful!"
    puts "Detected language: #{result[:detected_language]}"
    puts "Initial transcription: #{result[:initial_transcription][:text]}"

    if result[:improved_transcription]
      puts "Improved transcription: #{result[:improved_transcription][:text]}"
    end
  else
    puts "Audio file not found: #{audio_file_path}"
  end

rescue => e
  puts "Error in multi-language STT: #{e.message}"
end

# Example 7: Format conversion
puts "\n=== Example 7: STT Format Conversion ==="
begin
  audio_file_path = "./test_audio.wav"

  if File.exist?(audio_file_path)
    result = engine.call_worker(:stt_format_converter, {
      audio_file: audio_file_path,
      formats: ["json", "text", "srt", "vtt"]
    })

    puts "Format conversion successful!"
    result[:format_results].each do |format, transcription|
      puts "  - #{format.upcase}: #{transcription[:text].length} characters"
    end
  else
    puts "Audio file not found: #{audio_file_path}"
  end

rescue => e
  puts "Error in format conversion: #{e.message}"
end

# Example 8: Direct adapter usage
puts "\n=== Example 8: Direct Adapter Usage ==="
begin
  # Get the adapter directly
  adapter = engine.llms["stt_service"]

  audio_file_path = "./test_audio.wav"

  if File.exist?(audio_file_path)
    # Transcribe audio directly
    transcription_data = adapter.transcribe_audio(
      audio_file_path,
      language: "zh",
      temperature: 0.0,
      response_format: "json"
    )

    puts "Direct adapter usage successful!"
    puts "Transcribed text: #{transcription_data[:text]}"
    puts "Language: #{transcription_data[:language]}"
    puts "Duration: #{transcription_data[:duration]} seconds"

    # Get audio information
    audio_info = adapter.get_audio_info(audio_file_path)
    puts "Audio info - Format: #{audio_info[:format]}, Size: #{audio_info[:file_size]} bytes"

    # Detect language
    detected_language = adapter.detect_language(transcription_data[:text])
    puts "Detected language: #{detected_language}"

  else
    puts "Audio file not found: #{audio_file_path}"
  end

rescue => e
  puts "Error in direct adapter usage: #{e.message}"
end

puts "\n=== All examples completed ==="
puts "\nImportant Notes:"
puts "1. STT requires valid SILICONFLOW_API_KEY environment variable"
puts "2. Audio files must be in supported formats (mp3, wav, webm, etc.)"
puts "3. Maximum file size: 25MB"
puts "4. Supported languages: Chinese, English, Japanese, Korean"
puts "5. Response formats: json, text, srt, vtt"

# Clean up
File.delete('stt_config.yml') if File.exist?('stt_config.yml')