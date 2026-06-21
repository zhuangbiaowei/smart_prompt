# Video Generation Example for SmartPrompt
# This example demonstrates how to use the new VideoGenerationAdapter

require_relative '../lib/smart_prompt'

# Configuration for video generation capabilities
config = {
  "adapters" => {
    "multimodal" => "MultimodalAdapter",
    "image_generation" => "ImageGenerationAdapter",
    "video_generation" => "VideoGenerationAdapter"
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
    }
  },
  "default_llm" => "qwen_vl",
  "template_path" => "./templates",
  "worker_path" => "./workers",
  "logger_file" => "./logs/smart_prompt.log"
}

# Write config to file
File.write('video_generation_config.yml', config.to_yaml)

# Initialize engine
engine = SmartPrompt::Engine.new('video_generation_config.yml')

puts "=== SmartPrompt Video Generation Demo ==="

# Example 1: Simple text-to-video generation
puts "\n=== Example 1: Text-to-Video Generation ==="
begin
  result = engine.call_worker(:video_generator, {
    prompt: "A beautiful sunset over ocean waves, cinematic quality, slow motion",
    duration: 4,
    resolution: "720p",
    fps: 24,
    wait_for_completion: false, # Set to true to wait for completion
    download_to_file: false,     # Set to true to download video
    output_dir: "./generated_videos",
    filename_prefix: "sunset_video"
  })

  puts "Video generation job submitted successfully!"
  puts "Job ID: #{result[:video_data][:job_id]}"
  puts "Status: #{result[:video_data][:status]}"
  puts "Created at: #{result[:video_data][:created_at]}"

rescue => e
  puts "Error in video generation: #{e.message}"
  puts "Note: This example requires a valid SILICONFLOW_API_KEY environment variable"
  puts "Note: Video generation may take several minutes to complete"
end

# Example 2: Creative video generation with style
puts "\n=== Example 2: Creative Video Generation ==="
begin
  result = engine.call_worker(:creative_video_generator, {
    prompt: "A magical forest with glowing fairies and sparkling lights",
    video_style: "fantasy animation, Studio Ghibli style",
    duration: 4,
    resolution: "720p",
    fps: 24,
    wait_for_completion: false,
    download_to_file: false
  })

  puts "Creative video generation job submitted successfully!"
  puts "Job ID: #{result[:video_data][:job_id]}"
  puts "Status: #{result[:video_data][:status]}"

rescue => e
  puts "Error in creative video generation: #{e.message}"
end

# Example 3: Product video generation
puts "\n=== Example 3: Product Video Generation ==="
begin
  result = engine.call_worker(:product_video_generator, {
    prompt: "A modern smartphone rotating slowly on a marble surface",
    duration: 4,
    resolution: "720p",
    fps: 24,
    wait_for_completion: false,
    download_to_file: false
  })

  puts "Product video generation job submitted successfully!"
  puts "Job ID: #{result[:video_data][:job_id]}"
  puts "Status: #{result[:video_data][:status]}"

rescue => e
  puts "Error in product video generation: #{e.message}"
end

# Example 4: Check video status (if we have a job ID from previous examples)
puts "\n=== Example 4: Video Status Check ==="
begin
  # This example requires a valid job_id from a previous video generation
  # For demonstration, we'll show the method but skip execution
  puts "To check video status, use:"
  puts "result = engine.call_worker(:video_status_checker, {"
  puts "  job_id: 'YOUR_JOB_ID_HERE',"
  puts "  download_to_file: true"
  puts "})"

rescue => e
  puts "Error in status check: #{e.message}"
end

# Example 5: Direct adapter usage (without worker)
puts "\n=== Example 5: Direct Adapter Usage ==="
begin
  # Get the adapter directly
  adapter = engine.llms["video_gen"]

  # Generate video directly
  video_data = adapter.generate_video(
    "A butterfly flying through a flower garden, nature documentary style",
    duration: 4,
    resolution: "720p",
    fps: 24
  )

  puts "Direct adapter usage successful!"
  puts "Job ID: #{video_data[:job_id]}"
  puts "Status: #{video_data[:status]}"

  # Example of checking status
  # status = adapter.check_video_status(video_data[:job_id])
  # puts "Current status: #{status[:status]}, Progress: #{status[:progress]}"

rescue => e
  puts "Error in direct adapter usage: #{e.message}"
end

# Example 6: Batch video generation
puts "\n=== Example 6: Batch Video Generation ==="
begin
  result = engine.call_worker(:batch_video_generator, {
    prompts: [
      "A cat playing with a ball of yarn",
      "A dog running through a field",
      "A bird flying in the sky"
    ],
    duration: 3,
    resolution: "720p",
    fps: 24,
    wait_for_completion: false
  })

  puts "Batch video generation submitted successfully!"
  puts "Generated #{result[:batch_results].size} video jobs"
  result[:batch_results].each do |result|
    puts "  - Prompt: #{result[:prompt][0..50]}..."
    puts "    Job ID: #{result[:video_data][:job_id]}"
  end

rescue => e
  puts "Error in batch video generation: #{e.message}"
end

puts "\n=== All examples completed ==="
puts "\nImportant Notes:"
puts "1. Video generation is an asynchronous process"
puts "2. Jobs may take several minutes to complete"
puts "3. Use wait_for_completion: true to wait for completion"
puts "4. Use download_to_file: true to automatically download videos"
puts "5. Check status periodically using video_status_checker worker"

# Clean up
File.delete('video_generation_config.yml') if File.exist?('video_generation_config.yml')