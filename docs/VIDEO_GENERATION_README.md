# SmartPrompt Video Generation Guide

This guide explains how to use the new Video Generation capabilities in SmartPrompt.

## Overview

The Video Generation feature adds support for:
- **Text-to-Video Generation**: Generate videos from text prompts
- **Image-to-Video Generation**: Create videos from existing images
- **Asynchronous Processing**: Handle long-running video generation jobs
- **Status Monitoring**: Check progress and download completed videos

## Installation

Make sure you have the required dependencies:

```bash
gem install openai
```

## Configuration

Add the Video Generation adapter to your configuration:

```yaml
# config.yml
adapters:
  multimodal: "MultimodalAdapter"
  image_generation: "ImageGenerationAdapter"
  video_generation: "VideoGenerationAdapter"

llms:
  video_gen:
    adapter: "video_generation"
    url: "https://api.siliconflow.cn/v1/"
    api_key: "ENV[SILICONFLOW_API_KEY]"
    model: "Wan-AI/Wan2.2-T2V-A14B"

default_llm: "video_gen"
template_path: "./templates"
worker_path: "./workers"
logger_file: "./logs/smart_prompt.log"
```

## Available Workers

### 1. Video Generator Worker
Generate videos from text prompts.

```ruby
result = engine.call_worker(:video_generator, {
  prompt: "A beautiful sunset over ocean waves",
  duration: 4,                    # Optional: Video duration in seconds (1-10)
  resolution: "720p",            # Optional: "480p", "720p", "1080p"
  fps: 24,                       # Optional: Frames per second
  seed: 12345,                   # Optional: Random seed for reproducibility
  wait_for_completion: false,    # Optional: Wait for job completion
  download_to_file: false,       # Optional: Download video when completed
  output_dir: "./videos",        # Optional: Output directory
  filename_prefix: "video"       # Optional: Filename prefix
})
```

### 2. Image-to-Video Generator Worker
Create videos from existing images.

```ruby
result = engine.call_worker(:image_to_video_generator, {
  image_file: "./input.jpg",
  prompt: "Make the image come to life with animation",
  duration: 4,
  resolution: "720p",
  wait_for_completion: false,
  download_to_file: true
})
```

### 3. Video Status Checker Worker
Check the status of a video generation job.

```ruby
result = engine.call_worker(:video_status_checker, {
  job_id: "job_123456789",
  download_to_file: true,        # Optional: Download if completed
  output_dir: "./videos",
  filename_prefix: "completed_video"
})
```

### 4. Creative Video Generator Worker
Generate artistic videos with style control.

```ruby
result = engine.call_worker(:creative_video_generator, {
  prompt: "A magical forest with glowing fairies",
  video_style: "fantasy animation, Studio Ghibli style",
  duration: 4,
  resolution: "720p",
  wait_for_completion: true,
  download_to_file: true
})
```

### 5. Product Video Generator Worker
Generate professional product videos.

```ruby
result = engine.call_worker(:product_video_generator, {
  prompt: "Modern smartphone rotating on marble surface",
  duration: 4,
  resolution: "720p",
  wait_for_completion: true,
  download_to_file: true
})
```

### 6. Batch Video Generator Worker
Generate multiple videos from multiple prompts.

```ruby
result = engine.call_worker(:batch_video_generator, {
  prompts: [
    "A cat playing with yarn",
    "A dog running in a field",
    "A bird flying in the sky"
  ],
  duration: 3,
  resolution: "720p",
  wait_for_completion: false
})
```

## Direct Adapter Usage

You can also use the adapter directly without workers:

```ruby
# Get the adapter
adapter = engine.llms["video_gen"]

# Generate video
video_data = adapter.generate_video(
  "A butterfly flying through a garden",
  duration: 4,
  resolution: "720p",
  fps: 24
)

# Check status
status = adapter.check_video_status(video_data[:job_id])

# Wait for completion
completed_video = adapter.wait_for_video_completion(
  video_data[:job_id],
  check_interval: 10,    # Check every 10 seconds
  timeout: 600           # Timeout after 10 minutes
)

# Download video
if completed_video[:video_url]
  downloaded_file = adapter.download_video(
    completed_video[:video_url],
    "./videos/my_video.mp4"
  )
end
```

## Response Format

Video generation responses return video data objects:

```ruby
{
  job_id: "job_123456789",       # Unique job identifier
  status: "processing",          # "queued", "processing", "completed", "failed"
  video_url: "https://...",      # Video URL when completed
  progress: 50,                  # Progress percentage
  created_at: "2024-01-01...",   # Job creation timestamp
  updated_at: "2024-01-01..."    # Last update timestamp
}
```

## Supported Models

SiliconFlow supports various video generation models:
- `Wan-AI/Wan2.2-T2V-A14B` - Text-to-video generation
- `Wan-AI/Wan2.2-I2V-A14B` - Image-to-video generation

## Video Specifications

- **Duration**: 1-10 seconds
- **Resolution**: 480p, 720p, 1080p
- **FPS**: 24, 30, 60 frames per second
- **Format**: MP4

## Asynchronous Processing

Video generation is an asynchronous process:

1. **Submit Job**: Returns immediately with job ID
2. **Check Status**: Monitor progress periodically
3. **Wait for Completion**: Optionally wait for job to finish
4. **Download Result**: Download video when completed

## Error Handling

```ruby
begin
  result = engine.call_worker(:video_generator, params)
rescue SmartPrompt::LLMAPIError => e
  puts "API Error: #{e.message}"
rescue SmartPrompt::Error => e
  puts "General Error: #{e.message}"
rescue => e
  puts "Unexpected Error: #{e.message}"
end
```

## Best Practices

1. **Prompt Engineering**: Use detailed, time-sequential descriptions
2. **Video Length**: Keep videos under 10 seconds for best results
3. **Resolution**: Use 720p for good quality and reasonable processing time
4. **Batch Processing**: Use batch generation for multiple videos
5. **Status Monitoring**: Check status periodically for long-running jobs
6. **Error Recovery**: Implement retry logic for failed jobs

## Example

See `examples/video_generation_example.rb` for complete working examples.

## Troubleshooting

**Common Issues:**
- **API Key Error**: Ensure `SILICONFLOW_API_KEY` environment variable is set
- **Model Not Found**: Check that the specified model is available on SiliconFlow
- **Timeout Errors**: Video generation can take several minutes
- **Network Issues**: Check internet connectivity and API endpoint availability
- **File Permissions**: Ensure write permissions for output directories

**Job Status Meanings:**
- `queued`: Job is waiting to be processed
- `processing`: Job is currently being processed
- `completed`: Job finished successfully, video is available
- `failed`: Job failed, check error message
- `cancelled`: Job was cancelled by user or system