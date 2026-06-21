# SmartPrompt 多模态功能扩展

本文档介绍 SmartPrompt 新增的多模态功能，支持图像和视频分析。

## 新增适配器

### MultimodalAdapter

新的 `MultimodalAdapter` 扩展了原有的 OpenAI 兼容适配器，支持 SiliconFlow 的多模态视觉模型。

## 支持的功能

### 1. 图像分析
- 单张图像分析
- 多张图像比较
- 文档文字提取
- 场景描述

### 2. 视频分析
- 视频内容理解
- 帧提取控制
- 时序分析

### 3. 多模态对话
- 图像+文本组合输入
- 视频+文本组合输入
- 多图像+文本组合输入

## 快速开始

### 1. 配置

创建配置文件 `config/multimodal_config.yml`：

```yaml
adapters:
  multimodal: "MultimodalAdapter"

llms:
  qwen_vl:
    adapter: "multimodal"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    default_model: "Qwen/Qwen2.5-VL-7B-Instruct"

default_llm: "qwen_vl"
```

### 2. 创建工作流

在 `workers/` 目录中创建工作流定义：

```ruby
# workers/multimodal_workers.rb
SmartPrompt.define_worker :image_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: params[:question] },
        { type: "image_url", image_url: { url: params[:image_url], detail: "auto" } }
      ]
    }
  ]

  sys_msg("你是一个专业的图像分析助手。", params)
  params.merge(messages: messages)
  send_msg
end
```

### 3. 使用示例

```ruby
require 'smart_prompt'

# 初始化引擎
engine = SmartPrompt::Engine.new('config/multimodal_config.yml')

# 图像分析
result = engine.call_worker(:image_analyzer, {
  image_url: "https://example.com/image.jpg",
  question: "描述这张图片的内容"
})

puts result
```

## API 参考

### MultimodalAdapter 方法

#### `analyze_image(image_input, prompt, model = nil, detail: "auto", max_tokens: nil)`

分析单张图像。

**参数：**
- `image_input`: 图像 URL 或本地文件路径
- `prompt`: 分析提示文本
- `model`: 可选模型名称
- `detail`: 图像细节级别（"low", "high", "auto"）
- `max_tokens`: 最大输出 token 数

#### `analyze_video(video_input, prompt, model = nil, max_frames: 10, fps: 1, detail: "auto")`

分析视频内容。

**参数：**
- `video_input`: 视频 URL
- `prompt`: 分析提示文本
- `model`: 可选模型名称
- `max_frames`: 最大提取帧数
- `fps`: 帧率
- `detail`: 细节级别

#### `analyze_multiple_images(images, prompt, model = nil, detail: "auto")`

分析多张图像。

**参数：**
- `images`: 图像 URL 数组
- `prompt`: 分析提示文本
- `model`: 可选模型名称
- `detail`: 图像细节级别

### 消息格式

多模态消息使用标准 OpenAI 格式，支持 `image_url` 和 `video_url` 类型：

```ruby
messages = [
  {
    role: "user",
    content: [
      { type: "text", text: "分析这张图片" },
      {
        type: "image_url",
        image_url: {
          url: "https://example.com/image.jpg",
          detail: "auto"
        }
      }
    ]
  }
]
```

## 支持的多模态模型

### SiliconFlow 支持的多模态模型

- **Qwen2.5-VL 系列**: 视觉语言模型
- **Qwen3-Omni 系列**: 全模态模型（视觉/音频/视频）
- **DeepSeek-VL2**: 视觉语言模型
- **GLM 系列**: 视觉语言模型

## 配置参数

### 图像参数

- `detail`: 控制图像处理细节级别
  - `"low"`: 低分辨率，更快处理
  - `"high"`: 高分辨率，更准确
  - `"auto"`: 自动选择（推荐）

### 视频参数

- `max_frames`: 从视频中提取的最大帧数
- `fps`: 帧率，控制帧提取频率

## 错误处理

适配器包含完整的错误处理机制：

- 网络连接错误
- API 认证错误
- 文件格式错误
- 响应解析错误

## 示例工作流

### 1. 图像分析工作流

```ruby
SmartPrompt.define_worker :product_analyzer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: "分析这个产品图片，包括产品类型、颜色、特征和可能的用途" },
        { type: "image_url", image_url: { url: params[:product_image], detail: "high" } }
      ]
    }
  ]

  sys_msg("你是一个专业的产品分析师。", params)
  params.merge(messages: messages)
  send_msg
end
```

### 2. 视频摘要工作流

```ruby
SmartPrompt.define_worker :video_summarizer do
  use "qwen_vl"
  model "Qwen/Qwen2.5-VL-7B-Instruct"

  messages = [
    {
      role: "user",
      content: [
        { type: "text", text: "请总结这个视频的主要内容" },
        {
          type: "video_url",
          video_url: {
            url: params[:video_url],
            detail: "auto",
            max_frames: params[:max_frames] || 20,
            fps: params[:fps] || 2
          }
        }
      ]
    }
  ]

  sys_msg("你是一个专业的视频摘要助手。", params)
  params.merge(messages: messages)
  send_msg
end
```

## 最佳实践

1. **图像细节级别**: 对于文字提取使用 `"high"`，对于一般分析使用 `"auto"`
2. **视频帧率**: 根据视频长度调整，长视频使用较低帧率
3. **错误处理**: 总是包含适当的错误处理逻辑
4. **API 限制**: 注意 SiliconFlow 的 API 调用限制

## 故障排除

### 常见问题

1. **图像无法加载**: 检查 URL 可访问性或文件路径
2. **视频处理超时**: 减少 `max_frames` 或降低 `fps`
3. **API 认证失败**: 检查 API 密钥和环境变量
4. **内存不足**: 减少同时处理的图像数量

### 调试模式

启用详细日志记录：

```yaml
logger_file: "./logs/smart_prompt.log"
```

## 扩展开发

如需扩展更多多模态功能，可以参考现有的适配器架构，继承 `LLMAdapter` 类并实现相应的方法。