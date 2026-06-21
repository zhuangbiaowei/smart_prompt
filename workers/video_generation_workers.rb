# Video Generation Workers for SmartPrompt
# These workers demonstrate the new video generation capabilities

# Text-to-video generation worker
SmartPrompt.define_worker :video_generator do
  use "video_gen"
  model "Wan-AI/Wan2.2-T2V-A14B"

  # Prepare parameters for video generation
  generation_params = {
    prompt: params[:prompt],
    duration: params[:duration] || 4,
    resolution: params[:resolution] || "720p",
    fps: params[:fps] || 24,
    seed: params[:seed]
  }

  # Call the video generation adapter directly
  adapter = engine.llms["video_gen"]
  video_data = adapter.generate_video(
    generation_params[:prompt],
    model: params[:model],
    duration: generation_params[:duration],
    resolution: generation_params[:resolution],
    fps: generation_params[:fps],
    seed: generation_params[:seed]
  )

  # Wait for completion and download if requested
  if params[:wait_for_completion]
    completed_video = adapter.wait_for_video_completion(
      video_data[:job_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )

    # Download video if URL is available
    if completed_video[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./generated_videos"
      filename_prefix = params[:filename_prefix] || "generated_video"
      output_path = File.join(output_dir, "#{filename_prefix}_#{video_data[:job_id]}.mp4")

      downloaded_file = adapter.download_video(completed_video[:video_url], output_path)
      { video_data: completed_video, downloaded_file: downloaded_file }
    else
      { video_data: completed_video }
    end
  else
    { video_data: video_data }
  end
end

# Image-to-video generation worker
SmartPrompt.define_worker :image_to_video_generator do
  use "video_gen"
  model "Wan-AI/Wan2.2-I2V-A14B"

  # Prepare parameters for image-to-video generation
  generation_params = {
    image_file: params[:image_file],
    prompt: params[:prompt],
    duration: params[:duration] || 4,
    resolution: params[:resolution] || "720p",
    fps: params[:fps] || 24,
    seed: params[:seed]
  }

  # Call the image-to-video adapter directly
  adapter = engine.llms["video_gen"]
  video_data = adapter.create_video_from_image(
    generation_params[:image_file],
    generation_params[:prompt],
    model: params[:model],
    duration: generation_params[:duration],
    resolution: generation_params[:resolution],
    fps: generation_params[:fps],
    seed: generation_params[:seed]
  )

  # Wait for completion and download if requested
  if params[:wait_for_completion]
    completed_video = adapter.wait_for_video_completion(
      video_data[:job_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )

    # Download video if URL is available
    if completed_video[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./generated_videos"
      filename_prefix = params[:filename_prefix] || "image_to_video"
      output_path = File.join(output_dir, "#{filename_prefix}_#{video_data[:job_id]}.mp4")

      downloaded_file = adapter.download_video(completed_video[:video_url], output_path)
      { video_data: completed_video, downloaded_file: downloaded_file }
    else
      { video_data: completed_video }
    end
  else
    { video_data: video_data }
  end
end

# Video status checker worker
SmartPrompt.define_worker :video_status_checker do
  use "video_gen"

  # Check video generation status
  adapter = engine.llms["video_gen"]
  status_data = adapter.check_video_status(params[:job_id])

  # Download video if completed and requested
  if status_data[:status] == "completed" && status_data[:video_url] && params[:download_to_file]
    output_dir = params[:output_dir] || "./generated_videos"
    filename_prefix = params[:filename_prefix] || "video"
    output_path = File.join(output_dir, "#{filename_prefix}_#{params[:job_id]}.mp4")

    downloaded_file = adapter.download_video(status_data[:video_url], output_path)
    { status_data: status_data, downloaded_file: downloaded_file }
  else
    { status_data: status_data }
  end
end

# Creative video generation worker
SmartPrompt.define_worker :creative_video_generator do
  use "video_gen"
  model "Wan-AI/Wan2.2-T2V-A14B"

  # Prepare creative parameters
  creative_params = {
    prompt: params[:prompt] || "A beautiful animated scene",
    duration: params[:duration] || 4,
    resolution: params[:resolution] || "720p",
    fps: params[:fps] || 24,
    seed: params[:seed]
  }

  # Add creative style to prompt if specified
  style_prompt = creative_params[:prompt]
  if params[:video_style]
    style_prompt = "#{style_prompt}, in the style of #{params[:video_style]}"
  end

  adapter = engine.llms["video_gen"]
  video_data = adapter.generate_video(
    style_prompt,
    model: params[:model],
    duration: creative_params[:duration],
    resolution: creative_params[:resolution],
    fps: creative_params[:fps],
    seed: creative_params[:seed]
  )

  # Wait for completion and download if requested
  if params[:wait_for_completion]
    completed_video = adapter.wait_for_video_completion(
      video_data[:job_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )

    if completed_video[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./creative_videos"
      filename_prefix = params[:filename_prefix] || "creative_video"
      output_path = File.join(output_dir, "#{filename_prefix}_#{video_data[:job_id]}.mp4")

      downloaded_file = adapter.download_video(completed_video[:video_url], output_path)
      { video_data: completed_video, downloaded_file: downloaded_file }
    else
      { video_data: completed_video }
    end
  else
    { video_data: video_data }
  end
end

# Product video generation worker
SmartPrompt.define_worker :product_video_generator do
  use "video_gen"
  model "Wan-AI/Wan2.2-T2V-A14B"

  # Prepare product-specific parameters
  product_params = {
    prompt: params[:prompt] || "Professional product showcase",
    duration: params[:duration] || 4,
    resolution: params[:resolution] || "720p",
    fps: params[:fps] || 24,
    seed: params[:seed]
  }

  # Enhance prompt for product video
  enhanced_prompt = "Professional product video, smooth animation, cinematic quality, #{product_params[:prompt]}"

  adapter = engine.llms["video_gen"]
  video_data = adapter.generate_video(
    enhanced_prompt,
    model: params[:model],
    duration: product_params[:duration],
    resolution: product_params[:resolution],
    fps: product_params[:fps],
    seed: product_params[:seed]
  )

  # Wait for completion and download if requested
  if params[:wait_for_completion]
    completed_video = adapter.wait_for_video_completion(
      video_data[:job_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )

    if completed_video[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./product_videos"
      filename_prefix = params[:filename_prefix] || "product_video"
      output_path = File.join(output_dir, "#{filename_prefix}_#{video_data[:job_id]}.mp4")

      downloaded_file = adapter.download_video(completed_video[:video_url], output_path)
      { video_data: completed_video, downloaded_file: downloaded_file }
    else
      { video_data: completed_video }
    end
  else
    { video_data: video_data }
  end
end

# Batch video generation worker
SmartPrompt.define_worker :batch_video_generator do
  use "video_gen"
  model "Wan-AI/Wan2.2-T2V-A14B"

  results = []

  # Process multiple prompts
  prompts = params[:prompts] || [params[:prompt]]
  prompts.each_with_index do |prompt, index|
    generation_params = {
      prompt: prompt,
      duration: params[:duration] || 4,
      resolution: params[:resolution] || "720p",
      fps: params[:fps] || 24,
      seed: params[:seed] ? params[:seed] + index : nil
    }

    adapter = engine.llms["video_gen"]
    video_data = adapter.generate_video(
      generation_params[:prompt],
      model: params[:model],
      duration: generation_params[:duration],
      resolution: generation_params[:resolution],
      fps: generation_params[:fps],
      seed: generation_params[:seed]
    )

    results << {
      prompt: prompt,
      video_data: video_data,
      index: index
    }
  end

  { batch_results: results }
end