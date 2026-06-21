EN | [中文](./README.cn.md)

# SmartPrompt

[![Gem Version](https://badge.fury.io/rb/smart_prompt.svg)](https://badge.fury.io/rb/smart_prompt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

SmartPrompt is a powerful Ruby gem that provides an elegant domain-specific language (DSL) for building intelligent applications with Large Language Models (LLMs). It enables Ruby programs to seamlessly interact with various LLM providers while maintaining clean, composable, and highly customizable code architecture.

## 🚀 Key Features

### Multi-LLM Support
- **OpenAI API Compatible**: Full support for OpenAI GPT models and compatible APIs
- **Anthropic Claude**: Native support for Claude models with multimodal capabilities
- **SenseNova (商汤日日新)**: One adapter covers chat (商量), multimodal vision (图文多模态), Cupido embeddings (向量), and 秒画 text-to-image — see `examples/sensenova_example.rb`
- **智谱 AI (BigModel / GLM)**: One adapter covers all categories — chat (GLM-4), vision (GLM-4V), embeddings (embedding-3), text-to-image (CogView), text-to-video (CogVideoX), TTS (GLM-TTS), ASR (GLM-ASR) — see `examples/zhipu_example.rb`
- **Llama.cpp Integration**: Direct integration with local Llama.cpp servers
- **Extensible Adapters**: Easy-to-extend adapter system for new LLM providers
- **Unified Interface**: Same API regardless of the underlying LLM provider

### Multimodal AI Capabilities
- **Vision Models**: Support for image understanding and analysis
- **Image Generation**: Create images from text prompts using diffusion models
- **Video Generation**: Generate videos from text or image prompts
- **Text-to-Speech**: Convert text to natural-sounding speech
- **Speech-to-Text**: Transcribe audio files to text with multi-language support

### Flexible Architecture
- **Worker-based Tasks**: Define reusable workers for specific AI tasks
- **Template System**: ERB-based prompt templates with parameter injection
- **Intelligent History Management**: Session isolation, automatic compression, and multiple context strategies
- **Conversation Management**: Built-in conversation history and context management
- **Streaming Support**: Real-time response streaming for better user experience

### Advanced Features
- **Tool Calling**: Native support for function calling and tool integration
- **Retry Logic**: Robust error handling with configurable retry mechanisms
- **Embeddings**: Text embedding generation for semantic search and RAG applications
- **Configuration-driven**: YAML-based configuration for easy deployment management
- **Batch Processing**: Efficient processing of multiple files and tasks
- **Language Detection**: Automatic language identification from text and audio

### Production Ready
- **Comprehensive Logging**: Detailed logging for debugging and monitoring
- **Error Handling**: Graceful error handling with custom exception types  
- **Performance Optimized**: Efficient resource usage and response caching
- **Thread Safe**: Safe for concurrent usage in multi-threaded applications

## 📦 Installation

Add to your Gemfile:

```ruby
gem 'smart_prompt'
```

Then execute:
```bash
$ bundle install
```

Or install directly:
```bash
$ gem install smart_prompt
```

## 🛠️ Quick Start

### 1. Configuration

Create a YAML configuration file (`config/smart_prompt.yml`):

```yaml
# Adapter definitions
adapters:
  openai: OpenAIAdapter
  anthropic: AnthropicAdapter
# LLM configurations
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

# Model aliases
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

# Default settings
default_llm: SiliconFlow
template_path: "./templates"
worker_path: "./workers"
logger_file: "./logs/smart_prompt.log"
```

### 2. Create Prompt Templates

Create template files in your `templates/` directory:

**templates/chat.erb**:
```erb
You are a helpful assistant. Please respond to the following question:

Question: <%= question %>

Context: <%= context || "No additional context provided" %>
```

### 3. Define Workers

Create worker files in your `workers/` directory:

**workers/chat_worker.rb**:
```ruby
SmartPrompt.define_worker :chat_assistant do
  # Use a configured model alias
  use_model "deepseekv3.2"
  # Set system message
  sys_msg("You are a helpful AI assistant.", params)
  # Use template with parameters  
  prompt(:chat, {
    question: params[:question],
    context: params[:context]
  })
  # Send message and return response
  send_msg
end
```

### 4. Use in Your Application

```ruby
require 'smart_prompt'

# Initialize engine with config
engine = SmartPrompt::Engine.new('config/smart_prompt.yml')

# Execute worker
result = engine.call_worker(:chat_assistant, {
  question: "What is machine learning?",
  context: "We're discussing AI technologies"
})

puts result
```

## 📚 Advanced Usage

### Streaming Responses

```ruby
# Define streaming worker
SmartPrompt.define_worker :streaming_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("You are a helpful assistant.")
  prompt(params[:message])
  send_msg
end

# Use with streaming
engine.call_worker_by_stream(:streaming_chat, {
  message: "Tell me a story"
}) do |chunk, bytesize|
  print chunk.dig("choices", 0, "delta", "content")
end
```

### Gemma 4 12B Multimodal

Gemma 4 12B can be connected through OpenAI-compatible local servers such as LiteRT-LM, LM Studio, Ollama, or llama.cpp. SmartPrompt places images before text and audio after text to match Gemma 4 multimodal best practices.

```ruby
SmartPrompt.define_worker :gemma_multimodal_assistant do
  use_model "gemma4/12b"
  thinking params.fetch(:thinking, true)
  sys_msg("You are a precise local multimodal assistant.", params)

  image(params[:image], token_budget: params[:token_budget] || 280) if params[:image]
  video(params[:video], fps: 1, max_seconds: 60) if params[:video]
  audio(params[:audio]) if params[:audio]
  prompt(params[:message])

  request_options(response_format: { type: "json_object" }) if params[:json]
  send_msg
end
```

### Tool Integration

```ruby
# Define worker with tools
SmartPrompt.define_worker :assistant_with_tools do
  use "SiliconFlow"
  model "Qwen/Qwen3-235B-A22B"
  tools = [
    {
      type: "function",
      function: {
        name: "get_weather",
        description: "Get weather information for a location",
        parameters: {
          type: "object",
          properties: {
            location: {
              type: "string", 
              description: "The city and state"
            }
          },
          required: ["location"]
        }
      }
    }
  ]
  
  sys_msg("You can help with weather queries using available tools.", params)
  prompt(params[:message])
  params.merge(tools: tools)
  send_msg
end
```

### Conversation History

SmartPrompt provides intelligent conversation history management with session isolation, automatic compression, and multiple context strategies.

```ruby
# Basic usage with automatic history management
SmartPrompt.define_worker :conversational_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("You are a helpful assistant that remembers conversation context.")
  prompt(params[:message], with_history: true)
  send_msg
end

# Advanced usage with explicit session management
SmartPrompt.define_worker :session_chat do
  use "deepseek"
  model "deepseek-chat"
  
  # Use session_id for isolated conversations
  session_id = params[:session_id] || "default"
  
  # Configure session behavior
  session_config = {
    max_messages: 100,
    max_tokens: 4000,
    context_strategy: :sliding_window  # or :relevance_based, :summary_based, :hybrid
  }
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_id: session_id, session_config: session_config)
  send_msg
end
```

**History Management Features:**
- **Session Isolation**: Each conversation has independent history
- **Context Strategies**: Choose from sliding window, relevance-based, summary-based, or hybrid
- **Automatic Compression**: Reduce token usage while preserving context
- **Persistence**: Save and restore conversations across restarts
- **Performance**: LRU caching and async I/O for optimal performance

See [History Management Guide](HISTORY_MANAGEMENT_GUIDE.md) for detailed documentation.

### Embeddings Generation

```ruby
SmartPrompt.define_worker :text_embedder do
  use "SiliconFlow"
  model "BAAI/bge-m3"
  prompt params[:text]  
  embeddings(params[:dimensions] || 1024)
end

# Usage
embeddings = engine.call_worker(:text_embedder, {
  text: "Convert this text to embeddings",
  dimensions: 1024
})
```

### Multimodal AI Examples

#### Image Generation
```ruby
# Generate image from text prompt (SiliconFlow /v1/images/generations)
result = engine.call_worker(:image_generator, {
  prompt: "A beautiful sunset over mountains",
  image_size: "1024x1024",   # "widthxheight"; aliases: size:
  batch_size: 1,             # only Kolors; aliases: n:
  negative_prompt: "blurry, low quality",
  save_to_file: true,
  output_dir: "./generated_images"
})

puts "Generated #{result[:images].size} image(s)"
puts "First image URL: #{result[:images].first[:url]}"
puts "Saved files: #{result[:saved_files]}"
```

#### Video Generation
```ruby
# Generate video from text prompt
result = engine.call_worker(:video_generator, {
  prompt: "A cat playing with a ball of yarn",
  duration: 5,
  resolution: "720p",
  save_to_file: true,
  output_dir: "./generated_videos"
})

puts "Video generation started: #{result[:video_id]}"
puts "Check status with: engine.call_worker(:video_status, {video_id: '#{result[:video_id]}'})"
```

#### Text-to-Speech
```ruby
# Convert text to speech
result = engine.call_worker(:tts_synthesizer, {
  text: "Welcome to SmartPrompt, your AI assistant",
  voice: "alloy",
  speed: 1.0,
  save_to_file: true,
  output_dir: "./generated_audio"
})

puts "Audio file created: #{result[:audio_file][:file_path]}"
```

#### Speech-to-Text
```ruby
# Transcribe audio to text
result = engine.call_worker(:stt_transcriber, {
  audio_file: "./audio.wav",
  language: "en",
  response_format: "json"
})

puts "Transcribed text: #{result[:transcription][:text]}"
puts "Language: #{result[:transcription][:language]}"
```

#### Vision Analysis
```ruby
# Analyze image with vision model
result = engine.call_worker(:vision_analyzer, {
  image_file: "./image.jpg",
  prompt: "Describe what you see in this image"
})

puts "Analysis: #{result[:response]}"
```

## 🏗️ Architecture Overview

SmartPrompt follows a modular architecture:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   Application   │    │   SmartPrompt    │    │   LLM Provider  │
│                 │◄──►│     Engine       │◄──►│   (OpenAI/      │
│                 │    │                  │    │    Llama.cpp)   │
└─────────────────┘    └──────────────────┘    └─────────────────┘
                                │
                       ┌────────┼────────┐
                       │        │        │
                   ┌───▼───┐ ┌──▼──┐ ┌───▼────┐
                   │Workers│ │Conv.│ │Template│
                   │       │ │Mgmt │ │ System │
                   └───────┘ └─────┘ └────────┘
                                │
                       ┌────────┴────────┐
                       │                 │
                   ┌───▼────────┐  ┌─────▼──────┐
                   │  History   │  │Persistence │
                   │  Manager   │  │   Layer    │
                   └────────────┘  └────────────┘
```

### Core Components

- **Engine**: Central orchestrator managing configuration, adapters, and workers
- **Workers**: Reusable task definitions with embedded business logic
- **Conversation**: Context and message history management
- **History Manager**: Intelligent conversation history with session isolation and context strategies
- **Adapters**: LLM provider integrations (OpenAI, Anthropic, Llama.cpp, etc.)
- **Templates**: ERB-based prompt template system
- **Persistence Layer**: Save and restore conversation history across restarts

## 🔧 Configuration Reference

### Adapter Configuration

```yaml
adapters:
  openai: "OpenAIAdapter"              # For OpenAI API
  anthropic: "AnthropicAdapter"        # For Anthropic Claude API
  sensenova: "SenseNovaAdapter"        # For 商汤 SenseNova (chat/vision/embeddings/image)
  zhipu: "ZhipuAIAdapter"              # For 智谱 BigModel/GLM (chat/vision/embed/image/video/tts/asr)
  multimodal: "MultimodalAdapter"      # For vision models
  image_generation: "ImageGenerationAdapter"    # For image generation
  video_generation: "VideoGenerationAdapter"    # For video generation
  tts: "TTSAdapter"                    # For text-to-speech
  stt: "STTAdapter"                    # For speech-to-text
```

### LLM Configuration

```yaml
llms:
  # Text models
  gpt:
    adapter: "openai"
    api_key: ENV["OPENAI_API_KEY"]
    model: "gpt-4"
    temperature: 0.7

  # Anthropic Claude models
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

  # Custom Anthropic endpoint (for proxy or custom deployment)
  claude_custom:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    url: "https://your-custom-endpoint.com"
    model: "claude-3-5-sonnet-20241022"
    temperature: 0.7
    max_tokens: 4096

  # 商汤 SenseNova — one adapter covers all four model categories; just change `model`.
  # Free-tier models run on token.sensenova.cn/v1; paid models (SenseChat-5, SenseNova-V6-*
  # , Cupido) run on api.sensenova.cn/compatible-mode/v2 (returns 403 if your key lacks them).
  sensechat:                          # 商量 文本对话 (free-tier)
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-6.7-flash-lite"
    temperature: 0.7
    # Optional SenseNova sampling extras (forwarded to /chat/completions):
    # reasoning_effort: "medium"
    # max_completion_tokens: 4096
    # Paid: url https://api.sensenova.cn/compatible-mode/v2, model SenseChat-5

  sensevision:                        # 商量 图文多模态 (flash-lite is natively multimodal)
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-6.7-flash-lite"
    # Paid: url https://api.sensenova.cn/compatible-mode/v2, model SenseNova-V6-Pro

  senseembedding:                     # Cupido 向量模型 (paid; native endpoint)
    adapter: "sensenova"
    url: "https://api.sensenova.cn/compatible-mode/v2"
    embeddings_url: "https://api.sensenova.cn/v1/llm/embeddings"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "Cupido"

  senseimage:                         # 秒画 文生图 (sensenova-u1-fast; token.sensenova.cn base)
    adapter: "sensenova"
    url: "https://token.sensenova.cn/v1"
    image_url: "https://token.sensenova.cn/v1/images/generations"
    api_key: ENV["SENSENOVA_API_KEY"]
    model: "sensenova-u1-fast"
    # sensenova-u1-fast only accepts specific sizes (default 2048x2048); see
    # VALID_IMAGE_SIZES in sensenova_adapter.rb.

  # 智谱 AI (BigModel/GLM) — one adapter covers all categories; just change `model`.
  # Base https://open.bigmodel.cn/api/paas/v4 ; Bearer auth. Defaults use free-tier models.
  glm:                                # 文本对话 (free glm-4-flash; paid glm-4-plus/glm-5.2)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-4-flash"
    temperature: 0.7
    # CodeGeeX-4: set `coding: true` and model: codegeex-4 (uses the coding base)

  glm_vision:                         # 图文多模态 (free glm-4v-flash; paid glm-4v-plus)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-4v-flash"

  embedding:                          # 向量模型 (embedding-3; custom dimensions 256/512/1024/2048)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "embedding-3"
    dimensions: 1024

  cogview:                            # 文生图 (free cogview-3-flash; paid cogview-4/glm-image)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "cogview-3-flash"

  cogvideo:                           # 文生视频 (async submit->poll->download; free cogvideox-flash)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "cogvideox-flash"

  glm_tts:                            # 语音合成 (GLM-TTS)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-tts"

  glm_asr:                            # 语音识别 (GLM-ASR-2512)
    adapter: "zhipu"
    url: "https://open.bigmodel.cn/api/paas/v4"
    api_key: ENV["ZHIPUAI_API_KEY"]
    model: "glm-asr-2512"

  # Vision models
  vision:
    adapter: "multimodal"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "Qwen/Qwen2.5-VL-7B-Instruct"

  # Image generation (Kolors supports batch_size/guidance_scale; see Qwen-Image for cfg)
  image_gen:
    adapter: "image_generation"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "Kwai-Kolors/Kolors"

  # Video generation
  video_gen:
    adapter: "video_generation"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "Wan-AI/Wan2.2-T2V-A14B"

  # Text-to-speech
  tts_service:
    adapter: "tts"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "FunAudioLLM/CosyVoice2-0.5B"

  # Speech-to-text
  stt_service:
    adapter: "stt"
    url: "https://api.siliconflow.cn/v1/"
    api_key: ENV["SILICONFLOW_API_KEY"]
    model: "FunAudioLLM/CosyVoice2-0.5B"
```

### Model Alias Configuration

```yaml
models:
  model_alias:
    use: "llm_name"
    model: "model_identifier"
```

In a worker, `use_model "model_alias"` is equivalent to calling `use "llm_name"` and `model "model_identifier"`.

### Path Configuration

```yaml
template_path: "./templates"   # Directory for .erb templates
worker_path: "./workers"       # Directory for worker definitions  
logger_file: "./logs/app.log"  # Log file location
```

## 🧪 Testing

Run the test suite:

```bash
bundle exec rake test
```

For development, you can use the console:

```bash
bundle exec bin/console
```

## 🤝 Integration Examples

### With Rails Applications

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

# In your controller
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

### With Sidekiq Background Jobs

```ruby
class LLMProcessingJob < ApplicationJob
  def perform(task_type, parameters)
    engine = SmartPrompt::Engine.new('config/smart_prompt.yml')
    result = engine.call_worker(task_type.to_sym, parameters)
    
    # Process result...
    NotificationService.send_completion(result)
  end
end
```

## 🚀 Real-world Use Cases

- **Chatbots and Conversational AI**: Build sophisticated chatbots with context awareness
- **Content Generation**: Automated content creation with template-driven prompts
- **Code Analysis**: AI-powered code review and documentation generation
- **Customer Support**: Intelligent ticket routing and response suggestions
- **Data Processing**: LLM-powered data extraction and transformation
- **Educational Tools**: AI tutors and learning assistance systems
- **Multimedia Content Creation**: Generate images, videos, and audio content
- **Voice Interfaces**: Build voice-enabled applications with TTS and STT
- **Visual Analysis**: Image understanding and object detection applications
- **Accessibility Tools**: Audio descriptions, text-to-speech for visually impaired

## 🛣️ Roadmap

- [x] **Multimodal AI Support** - Vision, Image Generation, Video Generation, TTS, STT
- [ ] Additional LLM provider adapters (Anthropic Claude, Google PaLM)
- [ ] Visual prompt builder and management interface
- [ ] Enhanced caching and performance optimizations
- [ ] Integration with vector databases for RAG applications
- [ ] Built-in evaluation and testing framework for prompts
- [ ] Distributed worker execution support
- [ ] Real-time audio/video streaming support
- [ ] Advanced multimodal prompt chaining

## 🤝 Contributing

We welcome contributions! Please see [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -am 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE.txt](LICENSE.txt) file for details.

## 🙏 Acknowledgments

- Built with ❤️ by the SmartPrompt team
- Inspired by the need for elegant LLM integration in Ruby applications
- Thanks to all contributors and the Ruby community

## 📞 Support

- 📖 [Documentation](https://github.com/zhuangbiaowei/smart_prompt/wiki)
- 🐛 [Issue Tracker](https://github.com/zhuangbiaowei/smart_prompt/issues)
- 💬 [Discussions](https://github.com/zhuangbiaowei/smart_prompt/discussions)
- 📧 Email: zbw@kaiyuanshe.org

---

**SmartPrompt** - Making LLM integration in Ruby applications simple, powerful, and elegant.
