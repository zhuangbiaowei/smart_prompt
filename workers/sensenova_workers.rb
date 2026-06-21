# SenseNova workers for SmartPrompt
#
# These workers exercise the four SenseNova model categories through the unified
# SenseNovaAdapter. Reuses the standard DSL: `use`, `model`, `sys_msg`, `prompt`,
# `send_msg`, plus the multimodal/embedding/image helpers on Conversation.
#
# Note: `send_msg` transparently becomes streaming when the engine invokes the worker
# via call_worker_by_stream — so :sensenova_chat serves both sync and stream callers.

# 1. 商量 文本对话 (chat). Works for both call_worker and call_worker_by_stream.
SmartPrompt.define_worker :sensenova_chat do
  use "sensechat"
  model params[:model] if params[:model]
  sys_msg(params[:system] || "你是一个有帮助的中文助手，回答简洁准确。", params)
  prompt(params[:prompt] || "你好，请介绍一下你自己。")
  send_msg
end

# 2. 商量 图文多模态 (vision). Accepts a single image_url or image_urls (array).
#    The multimodal content array is added to the conversation directly so send_msg
#    sends it (send_msg reads @messages, not params).
SmartPrompt.define_worker :sensenova_vision do
  use "sensevision"
  model params[:model] if params[:model]
  sys_msg("你是一个专业的多模态图像分析助手，能够准确描述和分析图像内容。", params)

  content = [{ type: "text", text: params[:question] || "请描述这张图片中的内容。" }]
  images = params[:image_urls] || [params[:image_url]]
  images.each do |url|
    content << { type: "image_url", image_url: { url: url } }
  end
  add_message({ role: "user", content: content })

  send_msg
end

# 3. Cupido 向量模型 (embeddings). Returns a normalized numeric vector of the user text.
SmartPrompt.define_worker :sensenova_embed do
  use "senseembedding"
  model params[:model] if params[:model]
  prompt(params[:text] || "商汤科技日日新大模型")
  embeddings(params[:length] || 1024)
end

# 4. 秒画 文生图 (text-to-image). Returns the generated image(s); optionally saves to disk.
SmartPrompt.define_worker :sensenova_image do
  use "senseimage"
  model params[:model] if params[:model]

  images = generate_image(params[:prompt], params)

  if params[:save_to_file]
    saved = save_image(
      images,
      params[:output_dir] || "./generated_images",
      params[:filename_prefix] || "sensenova"
    )
    { images: images, saved_files: saved }
  else
    images
  end
end
