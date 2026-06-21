# 智谱 AI (Zhipu BigModel) workers for SmartPrompt
#
# One worker per model category, reusing the standard DSL (`use`, `model`, `sys_msg`,
# `prompt`, `send_msg`) and the media helpers. Chat/vision/embed/image go through
# Conversation-delegated methods; video/tts/asr reach the adapter directly via
# engine.llms[...] (same pattern as workers/video_generation_workers.rb).
#
# `send_msg` transparently becomes streaming when the engine invokes the worker via
# call_worker_by_stream — so :glm_chat serves both sync and stream callers.

# 1. 文本对话 (sync + stream)
SmartPrompt.define_worker :glm_chat do
  use "glm"
  model params[:model] if params[:model]
  sys_msg(params[:system] || "你是一个有帮助的中文助手，回答简洁准确。", params)
  prompt(params[:prompt] || "你好，请介绍一下智谱GLM。")
  send_msg
end

# 2. 图文多模态 (single image_url or image_urls array)
SmartPrompt.define_worker :glm_vision do
  use "glm_vision"
  model params[:model] if params[:model]
  sys_msg("你是一个专业的多模态图像分析助手。", params)

  content = [{ type: "text", text: params[:question] || "请描述这张图片中的内容。" }]
  images = params[:image_urls] || [params[:image_url]]
  images.each do |url|
    content << { type: "image_url", image_url: { url: url } }
  end
  add_message({ role: "user", content: content })

  send_msg
end

# 3. 向量模型
SmartPrompt.define_worker :glm_embed do
  use "embedding"
  model params[:model] if params[:model]
  prompt(params[:text] || "智谱GLM大模型")
  embeddings(params[:length] || 1024)
end

# 4. 文生图 (CogView / GLM-Image)
SmartPrompt.define_worker :cogview_image do
  use "cogview"
  model params[:model] if params[:model]
  images = generate_image(params[:prompt], params)
  if params[:save_to_file]
    saved = save_image(images, params[:output_dir] || "./generated_images", params[:filename_prefix] || "zhipu")
    { images: images, saved_files: saved }
  else
    images
  end
end

# 5. 文生视频 (async: submit -> wait -> download)
SmartPrompt.define_worker :cogvideo_video do
  use "cogvideo"
  model params[:model] if params[:model]
  adapter = engine.llms["cogvideo"]

  submitted = adapter.generate_video(params[:prompt], params)
  result = { submitted: submitted }

  if params[:wait_for_completion]
    completed = adapter.wait_for_video_completion(
      submitted[:task_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )
    if completed[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./generated_videos"
      prefix = params[:filename_prefix] || "zhipu_video"
      output_path = File.join(output_dir, "#{prefix}_#{submitted[:task_id]}.mp4")
      downloaded = adapter.download_video(completed[:video_url], output_path)
      result = { submitted: submitted, video: completed, downloaded_file: downloaded }
    else
      result = { submitted: submitted, video: completed }
    end
  end
  result
end

# 6. 语音合成 (GLM-TTS)
SmartPrompt.define_worker :glm_tts do
  use "glm_tts"
  model params[:model] if params[:model]
  adapter = engine.llms["glm_tts"]

  output_path = params[:output_path] || "./generated_audio/zhipu_tts.wav"
  info = adapter.synthesize_to_file(
    params[:text],
    output_path,
    voice: params[:voice],
    model: params[:model],
    response_format: params[:response_format] || "wav"
  )
  info
end

# 7. 语音识别 (GLM-ASR-2512)
SmartPrompt.define_worker :glm_asr do
  use "glm_asr"
  model params[:model] if params[:model]
  adapter = engine.llms["glm_asr"]

  adapter.transcribe_audio(
    params[:audio_file],
    model: params[:model],
    language: params[:language]
  )
end
