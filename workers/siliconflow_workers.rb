# 硅基流动 (SiliconFlow / SiliconCloud) workers for SmartPrompt
#
# One worker per model category, reusing the standard DSL (`use`, `model`, `sys_msg`,
# `prompt`, `send_msg`) and the media helpers. Chat/vision/embed/image/image-edit go
# through Conversation-delegated methods; rerank/video/tts/asr reach the adapter
# directly via engine.llms[...] (the methods Conversation does not delegate).
#
# `send_msg` transparently becomes streaming when the engine invokes the worker via
# call_worker_by_stream — so :siliconflow_chat serves both sync and stream callers.

# 1. 文本对话 (sync + stream)
SmartPrompt.define_worker :siliconflow_chat do
  use "sf_chat"
  model params[:model] if params[:model]
  sys_msg(params[:system] || "你是一个有帮助的中文助手，回答简洁准确。", params)
  prompt(params[:prompt] || "你好，请用一句话介绍硅基流动 SiliconFlow。")
  send_msg
end

# 2. 多模态对话 (vision / video / audio). Accepts image_url/video_url/audio_url,
#    a single media url, or arrays (image_urls).
SmartPrompt.define_worker :siliconflow_vision do
  use "sf_vision"
  model params[:model] if params[:model]
  sys_msg("你是一个专业的多模态分析助手，能够准确描述和分析图像/视频/音频内容。", params)

  content = [{ type: "text", text: params[:question] || "请描述这张图片中的内容。" }]
  ([params[:image_url]] + (params[:image_urls] || [])).compact.uniq.each do |url|
    content << { type: "image_url", image_url: { url: url } }
  end
  content << { type: "video_url", video_url: { url: params[:video_url] } } if params[:video_url]
  content << { type: "audio_url", audio_url: { url: params[:audio_url] } } if params[:audio_url]
  add_message({ role: "user", content: content })

  send_msg
end

# 3. 向量模型 (embeddings). Returns a normalized numeric vector of the user text.
SmartPrompt.define_worker :siliconflow_embed do
  use "sf_embed"
  model params[:model] if params[:model]
  prompt(params[:text] || "硅基流动 SiliconFlow 大模型")
  embeddings(params[:length] || 1024)
end

# 4. 重排 (rerank). Reorders params[:documents] by relevance to params[:query].
#    Conversation does not delegate rerank, so we reach the adapter directly.
SmartPrompt.define_worker :siliconflow_rerank do
  use "sf_rerank"
  model params[:model] if params[:model]
  adapter = engine.llms["sf_rerank"]

  adapter.rerank(
    params[:query],
    params[:documents] || [],
    model: params[:model],
    top_n: params[:top_n],
    return_documents: params[:return_documents],
  )
end

# 5. 文生图 (text-to-image). Returns the generated image(s); optionally saves to disk.
SmartPrompt.define_worker :siliconflow_image do
  use "sf_image"
  model params[:model] if params[:model]

  images = generate_image(params[:prompt], {
    model: params[:model],
    negative_prompt: params[:negative_prompt],
    image_size: params[:image_size] || params[:size],
    batch_size: params[:batch_size] || params[:n],
    seed: params[:seed],
    num_inference_steps: params[:num_inference_steps],
    guidance_scale: params[:guidance_scale],
  })

  if params[:save_to_file]
    saved = save_image(images, params[:output_dir] || "./generated_images", params[:filename_prefix] || "siliconflow")
    { images: images, saved_files: saved }
  else
    images
  end
end

# 6. 图像编辑 / 图生图 (Qwen-Image-Edit). Accepts image (and image2/image3 for
#    multi-image fusion) as local path, data URL, or http URL.
SmartPrompt.define_worker :siliconflow_image_edit do
  use "sf_image"
  model params[:model] || "Qwen/Qwen-Image-Edit-2509"

  images = edit_image(params[:prompt], {
    model: params[:model] || "Qwen/Qwen-Image-Edit-2509",
    image: params[:image] || params[:image_file],
    image2: params[:image2],
    image3: params[:image3],
    negative_prompt: params[:negative_prompt],
    seed: params[:seed],
    guidance_scale: params[:guidance_scale],
  })

  if params[:save_to_file]
    saved = save_image(images, params[:output_dir] || "./edited_images", params[:filename_prefix] || "siliconflow_edit")
    { images: images, saved_files: saved }
  else
    images
  end
end

# 7. 文生视频 / 图生视频 (async: submit -> poll -> download).
SmartPrompt.define_worker :siliconflow_video do
  use "sf_video"
  model params[:model] if params[:model]
  adapter = engine.llms["sf_video"]

  submitted = adapter.generate_video(params[:prompt], params)
  result = { submitted: submitted }

  if params[:wait_for_completion]
    completed = adapter.wait_for_video_completion(
      submitted[:request_id],
      check_interval: params[:check_interval] || 10,
      timeout: params[:timeout] || 600
    )
    if completed[:video_url] && params[:download_to_file]
      output_dir = params[:output_dir] || "./generated_videos"
      prefix = params[:filename_prefix] || "siliconflow_video"
      output_path = File.join(output_dir, "#{prefix}_#{submitted[:request_id]}.mp4")
      downloaded = adapter.download_video(completed[:video_url], output_path)
      result = { submitted: submitted, video: completed, downloaded_file: downloaded }
    else
      result = { submitted: submitted, video: completed }
    end
  end
  result
end

# 8. 语音合成 (TTS — CosyVoice2 / MOSS-TTSD). Saves the synthesized audio to disk.
SmartPrompt.define_worker :siliconflow_tts do
  use "sf_tts"
  model params[:model] if params[:model]
  adapter = engine.llms["sf_tts"]

  output_path = params[:output_path] || "./generated_audio/siliconflow_tts.mp3"
  info = adapter.synthesize_to_file(
    params[:text],
    output_path,
    voice: params[:voice],
    model: params[:model],
    response_format: params[:response_format] || "mp3",
    speed: params[:speed],
    language: params[:language],
  )
  info
end

# 9. 语音识别 (ASR — SenseVoiceSmall). Transcribes a local audio file.
SmartPrompt.define_worker :siliconflow_asr do
  use "sf_asr"
  model params[:model] if params[:model]
  adapter = engine.llms["sf_asr"]

  adapter.transcribe_audio(
    params[:audio_file],
    model: params[:model],
    language: params[:language],
  )
end
