# Multimodal Workers for SmartPrompt
# These workers demonstrate the new multimodal capabilities

# Image analysis worker
SmartPrompt.define_worker :image_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: params[:question] },
        { type: "image_url", image_url: { url: params[:image_url], detail: params[:detail] || "auto" } }
      ]
    }
  ]

  sys_msg("你是一个专业的图像分析助手，能够准确描述和分析图像内容。", params)
  params.merge(messages: messages)
  send_msg
end

# Video analysis worker
SmartPrompt.define_worker :video_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: params[:question] },
        {
          type: "video_url",
          video_url: {
            url: params[:video_url],
            detail: params[:detail] || "auto",
            max_frames: params[:max_frames] || 10,
            fps: params[:fps] || 1
          }
        }
      ]
    }
  ]

  sys_msg("你是一个专业的视频分析助手，能够准确描述和分析视频内容。", params)
  params.merge(messages: messages)
  send_msg
end

# Multiple images comparison worker
SmartPrompt.define_worker :multi_image_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  content = [{ type: "text", text: params[:question] }]
  params[:image_urls].each do |image_url|
    content << {
      type: "image_url",
      image_url: { url: image_url, detail: params[:detail] || "auto" }
    }
  end

  messages = [{ role: "user", content: content }]

  sys_msg("你是一个专业的图像比较助手，能够准确比较和分析多张图像的相似之处和不同之处。", params)
  params.merge(messages: messages)
  send_msg
end

# Document analysis worker (for images containing text)
SmartPrompt.define_worker :document_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: params[:question] || "请提取并分析这张图片中的文字内容" },
        { type: "image_url", image_url: { url: params[:image_url], detail: "high" } }
      ]
    }
  ]

  sys_msg("你是一个专业的文档分析助手，能够准确提取和分析图像中的文字内容。", params)
  params.merge(messages: messages)
  send_msg
end

# Scene description worker
SmartPrompt.define_worker :scene_describer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: "请详细描述这个场景，包括环境、人物、动作和情感氛围" },
        { type: "image_url", image_url: { url: params[:image_url], detail: "high" } }
      ]
    }
  ]

  sys_msg("你是一个专业的场景描述助手，能够生动详细地描述图像中的场景。", params)
  params.merge(messages: messages)
  send_msg
end