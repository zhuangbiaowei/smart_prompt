# Multimodal Example for SmartPrompt
# This example demonstrates how to use the new MultimodalAdapter

require_relative '../lib/smart_prompt'

# Configuration for multimodal capabilities
config = {
  "adapters" => {
    "multimodal" => "MultimodalAdapter"
  },
  "llms" => {
    "qwen_vl" => {
      "adapter" => "multimodal",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => ENV["SILICONFLOW_API_KEY"],
      "default_model" => "Qwen/Qwen2.5-VL-7B-Instruct"
    }
  },
  "default_llm" => "qwen_vl",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log"
}

# Write config to file
File.write('multimodal_config.yml', config.to_yaml)

# Initialize engine
engine = SmartPrompt::Engine.new('multimodal_config.yml')

# Example 1: Simple image analysis
puts "=== Example 1: Image Analysis ==="
result = engine.call_worker(:image_analyzer, {
  image_url: "https://example.com/image.jpg",
  question: "描述这张图片中的内容"
})
puts "Image Analysis Result: #{result}"

# Example 2: Video analysis
puts "\n=== Example 2: Video Analysis ==="
result = engine.call_worker(:video_analyzer, {
  video_url: "https://example.com/video.mp4",
  question: "这个视频的主要内容是什么？",
  max_frames: 15,
  fps: 2
})
puts "Video Analysis Result: #{result}"

# Example 3: Multiple images comparison
puts "\n=== Example 3: Multiple Images Comparison ==="
result = engine.call_worker(:multi_image_analyzer, {
  image_urls: [
    "https://example.com/image1.jpg",
    "https://example.com/image2.jpg"
  ],
  question: "比较这两张图片的相似之处和不同之处"
})
puts "Multi-Image Analysis Result: #{result}"

puts "\n=== All examples completed successfully ==="

# Clean up
File.delete('multimodal_config.yml') if File.exist?('multimodal_config.yml')