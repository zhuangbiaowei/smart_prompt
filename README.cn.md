[English](./README.md) | 中文

# SmartPrompt

[![Gem Version](https://badge.fury.io/rb/smart_prompt.svg)](https://badge.fury.io/rb/smart_prompt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

SmartPrompt 是一个强大的 Ruby gem，提供了优雅的领域特定语言（DSL），用于构建基于大型语言模型（LLM）的智能应用程序。它使 Ruby 程序能够无缝地与各种 LLM 服务提供商交互，同时保持清晰、可组合和高度可定制的代码架构。

## 🚀 核心特性

### 多 LLM 支持
- **OpenAI API 兼容**: 完全支持 OpenAI GPT 模型和兼容的 API
- **Anthropic Claude**: 原生支持 Claude 模型及多模态能力
- **商汤 SenseNova（日日新）**: 单一适配器覆盖商量文本对话、图文多模态、Cupido 向量、秒画文生图四类 API，详见 `examples/sensenova_example.rb`
- **智谱 AI（BigModel / GLM）**: 单一适配器覆盖全部模型类别——文本对话（GLM-4）、图文多模态（GLM-4V）、向量（embedding-3）、文生图（CogView）、文生视频（CogVideoX）、语音合成（GLM-TTS）、语音识别（GLM-ASR），详见 `examples/zhipu_example.rb`
- **Llama.cpp 集成**: 直接集成本地 Llama.cpp 服务器
- **可扩展适配器**: 易于扩展的适配器系统，支持新的 LLM 提供商
- **统一接口**: 无论底层 LLM 提供商如何，都使用相同的 API

### 多模态 AI 能力
- **视觉模型**: 支持图像理解和分析
- **图像生成**: 使用扩散模型从文本提示生成图像
- **视频生成**: 从文本或图像提示生成视频
- **文本转语音**: 将文本转换为自然语音
- **语音转文本**: 支持多语言的音频转文本转录

### 灵活架构
- **基于 Worker 的任务**: 为特定 AI 任务定义可重用的 Worker
- **模板系统**: 基于 ERB 的提示词模板，支持参数注入
- **智能历史管理**: 会话隔离、自动压缩和多种上下文策略
- **对话管理**: 内置对话历史和上下文管理
- **流式支持**: 实时响应流，提供更好的用户体验

### 高级功能
- **工具调用**: 原生支持函数调用和工具集成
- **重试逻辑**: 强大的错误处理机制，支持可配置的重试
- **嵌入向量**: 文本嵌入生成，用于语义搜索和 RAG 应用
- **配置驱动**: 基于 YAML 的配置，便于部署管理
- **批量处理**: 高效处理多个文件和任务
- **语言检测**: 从文本和音频自动识别语言

### 生产就绪
- **全面日志记录**: 详细的日志记录，用于调试和监控
- **错误处理**: 优雅的错误处理，包含自定义异常类型  
- **性能优化**: 高效的资源使用和响应缓存
- **线程安全**: 支持多线程应用中的并发使用

## 📦 安装

添加到你的 Gemfile：

```ruby
gem 'smart_prompt'
```

然后执行：
```bash
$ bundle install
```

或直接安装：
```bash
$ gem install smart_prompt
```

## 🛠️ 快速开始

### 1. 配置

创建 YAML 配置文件（`config/smart_prompt.yml`）：

```yaml
# 适配器定义
adapters:
  openai: OpenAIAdapter
  anthropic: AnthropicAdapter
# LLM 配置
llms:
  SiliconFlow:
    adapter: openai
    url: https://api.siliconflow.cn/v1/
    api_key: ENV["APIKey"]
    default_model: Qwen/Qwen2.5-7B-Instruct
  claude:
    adapter: anthropic
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: claude-3-5-sonnet-20241022
    temperature: 0.7
    max_tokens: 4096
  llamacpp:
    adapter: openai
    url: http://localhost:8080/    
  ollama:
    adapter: openai
    url: http://localhost:11434/
    default_model: deepseek-r1
  gemma4_local:
    adapter: openai
    url: http://localhost:8000/v1
    api_key: dummy
    default_model: gemma-4-12B-it
    temperature: 1.0
    top_p: 0.95
    top_k: 64
  deepseek:
    adapter: openai
    url: https://api.deepseek.com
    api_key: ENV["DSKEY"]
    default_model: deepseek-reasoner

# 模型别名配置
models:
  local/qwen3.5:
    use: local
    model: qwen3.5
  deepseekv3.2:
    use: SiliconFlow
    model: Pro/deepseek-ai/DeepSeek-V3.2
  gemma4/12b:
    use: gemma4_local
    model: gemma-4-12B-it
    max_tokens: 1024

# 默认设置
default_llm: SiliconFlow
template_path: "./templates"
worker_path: "./workers"
logger_file: "./logs/smart_prompt.log"
```

### 2. 创建提示词模板

在 `templates/` 目录中创建模板文件：

**templates/chat.erb**:
```erb
你是一个有用的助手。请回答以下问题：

问题：<%= question %>

背景：<%= context || "未提供额外背景信息" %>
```

### 3. 定义 Worker

在 `workers/` 目录中创建 worker 文件：

**workers/chat_worker.rb**:
```ruby
SmartPrompt.define_worker :chat_assistant do
  # 使用配置好的模型别名
  use_model "deepseekv3.2"
  # 设置系统消息
  sys_msg("你是一个有用的 AI 助手。", params)
  # 使用模板和参数  
  prompt(:chat, {
    question: params[:question],
    context: params[:context]
  })
  # 发送消息并返回响应
  send_msg
end
```

### 4. 在应用中使用

```ruby
require 'smart_prompt'

# 使用配置初始化引擎
engine = SmartPrompt::Engine.new('config/smart_prompt.yml')

# 执行 worker
result = engine.call_worker(:chat_assistant, {
  question: "什么是机器学习？",
  context: "我们正在讨论 AI 技术"
})

puts result
```

## 📚 高级用法

### 流式响应

```ruby
# 定义流式 worker
SmartPrompt.define_worker :streaming_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("你是一个有用的助手。")
  prompt(params[:message])
  send_msg
end

# 使用流式处理
engine.call_worker_by_stream(:streaming_chat, {
  message: "给我讲个故事"
}) do |chunk, bytesize|
  print chunk.dig("choices", 0, "delta", "content")
end
```

### Gemma 4 12B 多模态

Gemma 4 12B 可以通过 LiteRT-LM、LM Studio、Ollama、llama.cpp 等 OpenAI 兼容本地服务接入。SmartPrompt 会把图片放在文本前、音频放在文本后，以匹配 Gemma 4 的多模态最佳实践。

```ruby
SmartPrompt.define_worker :gemma_multimodal_assistant do
  use_model "gemma4/12b"
  thinking params.fetch(:thinking, true)
  sys_msg("你是一个严谨的本地多模态助手。", params)

  image(params[:image], token_budget: params[:token_budget] || 280) if params[:image]
  video(params[:video], fps: 1, max_seconds: 60) if params[:video]
  audio(params[:audio]) if params[:audio]
  prompt(params[:message])

  request_options(response_format: { type: "json_object" }) if params[:json]
  send_msg
end
```

### 工具集成

```ruby
# 定义带工具的 worker
SmartPrompt.define_worker :assistant_with_tools do
  use "SiliconFlow"
  model "Qwen/Qwen3-235B-A22B"
  tools = [
    {
      type: "function",
      function: {
        name: "get_weather",
        description: "获取指定位置的天气信息",
        parameters: {
          type: "object",
          properties: {
            location: {
              type: "string", 
              description: "城市和省份"
            }
          },
          required: ["location"]
        }
      }
    }
  ]
  
  sys_msg("你可以使用可用的工具帮助处理天气查询。", params)
  prompt(params[:message])
  params.merge(tools: tools)
  send_msg
end
```

### 对话历史

SmartPrompt 提供智能对话历史管理，支持会话隔离、自动压缩和多种上下文策略。

```ruby
# 基本用法，自动管理历史
SmartPrompt.define_worker :conversational_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("你是一个记住对话上下文的有用助手。")
  prompt(params[:message], with_history: true)
  send_msg
end

# 高级用法，显式会话管理
SmartPrompt.define_worker :session_chat do
  use "deepseek"
  model "deepseek-chat"

  # 使用 session_id 进行隔离的对话
  session_id = params[:session_id] || "default"

  # 配置会话行为
  session_config = {
    max_messages: 100,
    max_tokens: 4000,
    context_strategy: :sliding_window  # 或 :relevance_based, :summary_based, :hybrid
  }

  sys_msg("你是一个有用的助手。", params)
  prompt(params[:message], with_history: true)
  params.merge(session_id: session_id, session_config: session_config)
  send_msg
end
```

**历史管理功能：**
- **会话隔离**: 每个对话都有独立的历史记录
- **上下文策略**: 可选择滑动窗口、基于相关性、基于摘要或混合策略
- **自动压缩**: 在保留上下文的同时减少 token 使用量
- **持久化**: 跨重启保存和恢复对话
- **性能优化**: LRU 缓存和异步 I/O 以获得最佳性能

详见 [历史管理指南](HISTORY_MANAGEMENT_GUIDE.md)。

### 嵌入向量生成

```ruby
SmartPrompt.define_worker :text_embedder do
  use "SiliconFlow"
  model "BAAI/bge-m3"
  prompt params[:text]  
  embeddings(params[:dimensions] || 1024)
end

# 使用方法
embeddings = engine.call_worker(:text_embedder, {
  text: "将此文本转换为嵌入向量",
  dimensions: 1024
})

### 多模态 AI 示例

#### 图像生成
```ruby
# 从文本提示生成图像
result = engine.call_worker(:image_generator, {
  prompt: "山间美丽的日落",
  size: "1024x1024",
  quality: "standard",
  save_to_file: true,
  output_dir: "./generated_images"
})

puts "图像已生成: #{result[:image_file][:file_path]}"
```

#### 视频生成
```ruby
# 从文本提示生成视频
result = engine.call_worker(:video_generator, {
  prompt: "一只猫在玩毛线球",
  duration: 5,
  resolution: "720p",
  save_to_file: true,
  output_dir: "./generated_videos"
})

puts "视频生成已开始: #{result[:video_id]}"
puts "检查状态: engine.call_worker(:video_status, {video_id: '#{result[:video_id]}'})"
```

#### 文本转语音
```ruby
# 将文本转换为语音
result = engine.call_worker(:tts_synthesizer, {
  text: "欢迎使用 SmartPrompt，您的 AI 助手",
  voice: "alloy",
  speed: 1.0,
  save_to_file: true,
  output_dir: "./generated_audio"
})

puts "音频文件已创建: #{result[:audio_file][:file_path]}"
```

#### 语音转文本
```ruby
# 将音频转录为文本
result = engine.call_worker(:stt_transcriber, {
  audio_file: "./audio.wav",
  language: "zh",
  response_format: "json"
})

puts "转录文本: #{result[:transcription][:text]}"
puts "语言: #{result[:transcription][:language]}"
```

#### 视觉分析
```ruby
# 使用视觉模型分析图像
result = engine.call_worker(:vision_analyzer, {
  image_file: "./image.jpg",
  prompt: "描述你在这张图片中看到了什么"
})

puts "分析结果: #{result[:response]}"
```
```

## 🏗️ 架构概述

SmartPrompt 采用模块化架构：

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│     应用程序     │    │   SmartPrompt    │    │   LLM 提供商    │
│                 │◄──►│      引擎        │◄──►│   (OpenAI/      │
│                 │    │                  │    │    Llama.cpp)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌────────┼────────┐
                       │        │        │
                   ┌───▼───┐ ┌──▼──┐ ┌───▼────┐
                   │Worker │ │对话 │ │ 模板   │
                   │       │ │管理 │ │ 系统   │
                   └───────┘ └─────┘ └────────┘
                                │
                       ┌────────┴────────┐
                       │                 │
                   ┌───▼────────┐  ┌─────▼──────┐
                   │  历史管理  │  │  持久化层  │
                   │    器      │  │            │
                   └────────────┘  └────────────┘
```

### 核心组件

- **引擎（Engine）**: 中央编排器，管理配置、适配器和 Worker
- **Worker**: 包含嵌入业务逻辑的可重用任务定义
- **对话（Conversation）**: 上下文和消息历史管理
- **历史管理器**: 智能对话历史，支持会话隔离和上下文策略
- **适配器（Adapters）**: LLM 提供商集成（OpenAI、Anthropic、Llama.cpp 等）
- **模板（Templates）**: 基于 ERB 的提示词模板系统
- **持久化层（Persistence Layer）**: 跨重启保存和恢复对话历史

## 🔧 配置参考

### 适配器配置

```yaml
adapters:
  openai: "OpenAIAdapter"              # 用于 OpenAI API
  anthropic: "AnthropicAdapter"        # 用于 Anthropic Claude API
  sensenova: "SenseNovaAdapter"        # 用于商汤 SenseNova（对话/视觉/向量/文生图）
  zhipu: "ZhipuAIAdapter"              # 用于智谱 BigModel/GLM（对话/视觉/向量/图/视频/语音）
  multimodal: "MultimodalAdapter"      # 用于视觉模型
  image_generation: "ImageGenerationAdapter"    # 用于图像生成
  video_generation: "VideoGenerationAdapter"    # 用于视频生成
  tts: "TTSAdapter"                    # 用于文本转语音
  stt: "STTAdapter"                    # 用于语音转文本
```

### LLM 配置

```yaml
llms:
  # 文本模型
  gpt:
    adapter: "openai"
    api_key: ENV["OPENAI_API_KEY"]
    model: "gpt-4"
    temperature: 0.7

  # Anthropic Claude 模型
  claude:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-5-sonnet-20241022"
    temperature: 0.7
    max_tokens: 4096

  claude_opus:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-opus-20240229"
    temperature: 0.7
    max_tokens: 4096

  claude_haiku:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-5-haiku-20241022"
    temperature: 0.7
    max_tokens: 4096

  # 自定义 Anthropic 端点（用于代理或自定义部署）
  claude_custom:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    url: "https://your-custom-endpoint.com"
    model: "claude-3-5-sonnet-20241022"
    temperature: 0.7
    max_tokens: 4096

  # 商汤 SenseNova —— 单一适配器覆盖四类模型，只需切换 model。
  # 免费模型走 token.sensenova.cn/v1；付费模型（SenseChat-5、SenseNova-V6-*、Cupido）
  # 走 api.sensenova.cn/compatible-mode/v2（key 无权限时返回 403）。
  sensechat:                          # 商量 文本对话（免费档）
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-6.7-flash-lite"
    temperature: 0.7
    # 可选 SenseNova 采样参数（会透传到 /chat/completions）：
    # reasoning_effort: "medium"
    # max_completion_tokens: 4096
    # 付费：url https://api.sensenova.cn/compatible-mode/v2，model SenseChat-5

  sensevision:                        # 商量 图文多模态（flash-lite 原生多模态）
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-6.7-flash-lite"
    # 付费：url https://api.sensenova.cn/compatible-mode/v2，model SenseNova-V6-Pro

  senseembedding:                     # Cupido 向量模型（付费；原生端点）
    adapter: "sensenova"
    url: "https://api.sensenova.cn/compatible-mode/v2"
    embeddings_url: "https://api.sensenova.cn/v1/llm/embeddings"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "Cupido"

  senseimage:                         # 秒画 文生图（sensenova-u1-fast，token.sensenova.cn base）
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    image_url: "https://token.sensenova.cn/v1/images/generations"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-u1-fast"
    # sensenova-u1-fast 只接受特定尺寸（默认 2048x2048），见 sensenova_adapter.rb 的 VALID_IMAGE_SIZES

  # 智谱 AI（BigModel/GLM）—— 单一适配器覆盖全部类别，只需切换 model。
  # base https://open.bigmodel.cn/api/paas/v4 ，Bearer 鉴权。默认用免费模型。
  glm:                                # 文本对话（免费 glm-4-flash；付费 glm-4-plus/glm-5.2）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-4-flash"
    temperature: 0.7
    # CodeGeeX-4：设 `coding: true` 并 model: codegeex-4（走 coding base）

  glm_vision:                         # 图文多模态（免费 glm-4v-flash；付费 glm-4v-plus）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-4v-flash"

  embedding:                          # 向量模型（embedding-3；可自定义维度 256/512/1024/2048）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "embedding-3"
    dimensions: 1024

  cogview:                            # 文生图（免费 cogview-3-flash；付费 cogview-4/glm-image）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "cogview-3-flash"

  cogvideo:                           # 文生视频（异步 提交->轮询->下载；免费 cogvideox-flash）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "cogvideox-flash"

  glm_tts:                            # 语音合成（GLM-TTS）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-tts"

  glm_asr:                            # 语音识别（GLM-ASR-2512）
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-asr-2512"

  # 视觉模型
  vision:
    adapter: "multimodal"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "Qwen/Qwen2.5-VL-7B-Instruct"

  # 图像生成
  image_gen:
    adapter: "image_generation"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "stabilityai/stable-diffusion-xl-base-1.0"

  # 视频生成
  video_gen:
    adapter: "video_generation"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "Wan-AI/Wan2.2-T2V-A14B"

  # 文本转语音
  tts_service:
    adapter: "tts"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "FunAudioLLM/CosyVoice2-0.5B"

  # 语音转文本
  stt_service:
    adapter: "stt"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "FunAudioLLM/CosyVoice2-0.5B"
```

### 模型别名配置

```yaml
models:
  model_alias:
    use: "llm_name"
    model: "model_identifier"
```

在 worker 中，`use_model "model_alias"` 等价于调用 `use "llm_name"` 和 `model "model_identifier"`。

### 路径配置

```yaml
template_path: "./templates"   # .erb 模板目录
worker_path: "./workers"       # worker 定义目录  
logger_file: "./logs/app.log"  # 日志文件位置
```

## 🧪 测试

运行测试套件：

```bash
bundle exec rake test
```

开发时，可以使用控制台：

```bash
bundle exec bin/console
```

## 🤝 集成示例

### 与 Rails 应用集成

```ruby
# config/initializers/smart_prompt.rb
class SmartPromptService
  def self.engine
    @engine ||= SmartPrompt::Engine.new(
      Rails.root.join('config', 'smart_prompt.yml')
    )
  end
  
  def self.chat(message, context: nil)
    engine.call_worker(:chat_assistant, {
      question: message,
      context: context
    })
  end
end

# 在控制器中使用
class ChatController < ApplicationController
  def create
    response = SmartPromptService.chat(
      params[:message],
      context: session[:conversation_context]
    )
    
    render json: { response: response }
  end
end
```

### 与 Sidekiq 后台任务集成

```ruby
class LLMProcessingJob < ApplicationJob
  def perform(task_type, parameters)
    engine = SmartPrompt::Engine.new('config/smart_prompt.yml')
    result = engine.call_worker(task_type.to_sym, parameters)
    
    # 处理结果...
    NotificationService.send_completion(result)
  end
end
```

## 🚀 实际应用场景

- **聊天机器人和对话式 AI**: 构建具有上下文感知能力的复杂聊天机器人
- **内容生成**: 基于模板驱动的提示词进行自动化内容创建
- **代码分析**: AI 驱动的代码审查和文档生成
- **客户支持**: 智能工单路由和响应建议
- **数据处理**: LLM 驱动的数据提取和转换
- **教育工具**: AI 导师和学习辅助系统
- **多媒体内容创作**: 生成图像、视频和音频内容
- **语音界面**: 使用 TTS 和 STT 构建语音应用
- **视觉分析**: 图像理解和目标检测应用
- **无障碍工具**: 为视障人士提供音频描述、文本转语音

## 🛣️ 发展路线图

- [x] **多模态 AI 支持** - 视觉、图像生成、视频生成、TTS、STT
- [ ] 新增 LLM 提供商适配器（Anthropic Claude、Google PaLM）
- [ ] 可视化提示词构建器和管理界面
- [ ] 增强缓存和性能优化
- [ ] 与向量数据库集成，支持 RAG 应用
- [ ] 内置提示词评估和测试框架
- [ ] 分布式 worker 执行支持
- [ ] 实时音视频流支持
- [ ] 高级多模态提示链

## 🤝 贡献

我们欢迎贡献！请查看 [CONTRIBUTING.md](CONTRIBUTING.md) 了解指南。

1. Fork 本仓库
2. 创建你的功能分支（`git checkout -b feature/amazing-feature`）
3. 提交你的更改（`git commit -am 'Add amazing feature'`）
4. 推送到分支（`git push origin feature/amazing-feature`）
5. 开启一个 Pull Request

## 📄 许可证

本项目使用 MIT 许可证 - 详情请查看 [LICENSE.txt](LICENSE.txt) 文件。

## 🙏 致谢

- 由 SmartPrompt 团队用 ❤️ 构建
- 受到在 Ruby 应用中优雅集成 LLM 需求的启发
- 感谢所有贡献者和 Ruby 社区

## 📞 支持

- 📖 [文档](https://github.com/zhuangbiaowei/smart_prompt/wiki)
- 🐛 [问题追踪](https://github.com/zhuangbiaowei/smart_prompt/issues)
- 💬 [讨论区](https://github.com/zhuangbiaowei/smart_prompt/discussions)
- 📧 邮箱：zbw@kaiyuanshe.org

---

**SmartPrompt** - 让 Ruby 应用中的 LLM 集成变得简单、强大且优雅。
