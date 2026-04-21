[English](./README.md) | 中文

# SmartPrompt

[![Gem Version](https://badge.fury.io/rb/smart_prompt.svg)](https://badge.fury.io/rb/smart_prompt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

SmartPrompt 是一个强大的 Ruby gem，提供了优雅的领域特定语言（DSL），用于构建基于大型语言模型（LLM）的智能应用程序。它使 Ruby 程序能够无缝地与各种 LLM 服务提供商交互，同时保持清晰、可组合和高度可定制的代码架构。

## 🚀 核心特性

### 多 LLM 支持
- **OpenAI API 兼容**: 完全支持 OpenAI GPT 模型和兼容的 API
- **Llama.cpp 集成**: 直接集成本地 Llama.cpp 服务器  
- **可扩展适配器**: 易于扩展的适配器系统，支持新的 LLM 提供商
- **统一接口**: 无论底层 LLM 提供商如何，都使用相同的 API

### 灵活架构
- **基于 Worker 的任务**: 为特定 AI 任务定义可重用的 Worker
- **模板系统**: 基于 ERB 的提示词模板，支持参数注入
- **对话管理**: 内置对话历史和上下文管理
- **流式支持**: 实时响应流，提供更好的用户体验

### 高级功能
- **工具调用**: 原生支持函数调用和工具集成
- **重试逻辑**: 强大的错误处理机制，支持可配置的重试
- **嵌入向量**: 文本嵌入生成，用于语义搜索和 RAG 应用
- **配置驱动**: 基于 YAML 的配置，便于部署管理

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
# LLM 配置
llms:
  SiliconFlow:
    adapter: openai
    url: https://api.siliconflow.cn/v1/
    api_key: ENV["APIKey"]
    default_model: Qwen/Qwen2.5-7B-Instruct
  local:
    adapter: openai
    url: http://localhost:8080/    
  ollama:
    adapter: openai
    url: http://localhost:11434/
    default_model: deepseek-r1
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

```ruby
SmartPrompt.define_worker :conversational_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("你是一个记住对话上下文的有用助手。")
  prompt(params[:message], with_history: true)
  send_msg
end
```

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
```

### 核心组件

- **引擎（Engine）**: 中央编排器，管理配置、适配器和 Worker
- **Worker**: 包含嵌入业务逻辑的可重用任务定义
- **对话（Conversation）**: 上下文和消息历史管理
- **适配器（Adapters）**: LLM 提供商集成（OpenAI、Llama.cpp 等）
- **模板（Templates）**: 基于 ERB 的提示词模板系统

## 🔧 配置参考

### 适配器配置

```yaml
adapters:
  openai: "OpenAIAdapter"      # 用于 OpenAI API
```

### LLM 配置

```yaml
llms:
  model_name:
    adapter: "adapter_name"
    api_key: "your_api_key"     # 可以使用 ENV['KEY_NAME']
    url: "https://api.url"
    model: "model_identifier"
    temperature: 0.7
    # 其他提供商特定选项
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

## 🛣️ 发展路线图

- [ ] 新增 LLM 提供商适配器（Anthropic Claude、Google PaLM）
- [ ] 可视化提示词构建器和管理界面
- [ ] 增强缓存和性能优化
- [ ] 与向量数据库集成，支持 RAG 应用
- [ ] 内置提示词评估和测试框架
- [ ] 分布式 worker 执行支持

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
