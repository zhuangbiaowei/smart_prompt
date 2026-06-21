# Image Generation Example for SmartPrompt
#
# Demonstrates calling SiliconFlow's image generation API
# (POST /v1/images/generations) through the ImageGenerationAdapter.
#
# Requires a valid SiliconFlow API key in the SILICONFLOW_API_KEY (or APIKey)
# environment variable.

require_relative "../lib/smart_prompt"

api_key = ENV["SILICONFLOW_API_KEY"] || ENV["APIKey"]

# Configuration for image generation capabilities.
config = {
  "adapters" => {
    "image_generation" => "ImageGenerationAdapter",
  },
  "llms" => {
    "image_gen" => {
      "adapter" => "image_generation",
      "url" => "https://api.siliconflow.cn/v1/",
      "api_key" => api_key,
      # Kolors supports batch_size, guidance_scale and a range of image_size values.
      "model" => "Kwai-Kolors/Kolors",
    },
  },
  "default_llm" => "image_gen",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log",
}

# Write config to file
File.write("image_generation_config.yml", config.to_yaml)

# Initialize engine
engine = SmartPrompt::Engine.new("image_generation_config.yml")

puts "=== SmartPrompt Image Generation Demo ==="

unless api_key
  puts "Note: SILICONFLOW_API_KEY is not set — the API calls below will fail at the network layer."
end

# Example 1: Simple text-to-image generation (Kolors)
puts "\n=== Example 1: Text-to-Image Generation ==="
begin
  result = engine.call_worker(:image_generator, {
    prompt: "A beautiful sunset over a mountain lake with pine trees, digital art style",
    image_size: "1024x1024",
    batch_size: 1,
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "sunset",
  })

  puts "Image generation successful!"
  puts "Generated images: #{result[:images].size}"
  puts "First image URL: #{result[:images].first[:url]}"
  puts "Saved files: #{result[:saved_files]}"
rescue => e
  puts "Error in image generation: #{e.message}"
end

# Example 2: Art generation with a specific style (more inference steps)
puts "\n=== Example 2: Artistic Image Generation ==="
begin
  result = engine.call_worker(:art_generator, {
    prompt: "A mystical forest with glowing mushrooms and fairies",
    art_style: "fantasy art, detailed painting",
    image_size: "960x1280",
    num_inference_steps: 30,
    guidance_scale: 7.5,
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "fantasy_forest",
  })

  puts "Art generation successful!"
  puts "Generated art images: #{result[:images].size}"
  puts "Saved files: #{result[:saved_files]}"
rescue => e
  puts "Error in art generation: #{e.message}"
end

# Example 3: Product image generation (with a negative prompt)
puts "\n=== Example 3: Product Image Generation ==="
begin
  result = engine.call_worker(:product_image_generator, {
    prompt: "A modern smartphone on a marble surface",
    image_size: "1024x1024",
    negative_prompt: "text, watermark, logo",
    save_to_file: true,
    output_dir: "./generated_images",
    filename_prefix: "smartphone",
  })

  puts "Product image generation successful!"
  puts "Generated product images: #{result[:images].size}"
  puts "Saved files: #{result[:saved_files]}"
rescue => e
  puts "Error in product image generation: #{e.message}"
end

# Example 4: Direct adapter usage (without a worker)
puts "\n=== Example 4: Direct Adapter Usage ==="
begin
  adapter = engine.llms["image_gen"]

  images = adapter.generate_image(
    "A cute robot reading a book in a cozy library",
    image_size: "1024x1024",
    seed: 42,
  )

  puts "Direct adapter usage successful!"
  puts "Generated #{images.size} image(s)"
  puts "First image URL: #{images.first[:url]}"

  # Optionally save to disk
  saved = adapter.save_image(images, "./generated_images", "robot")
  puts "Saved files: #{saved}"
rescue => e
  puts "Error in direct adapter usage: #{e.message}"
end

puts "\n=== All examples completed ==="

# Clean up
File.delete("image_generation_config.yml") if File.exist?("image_generation_config.yml")
