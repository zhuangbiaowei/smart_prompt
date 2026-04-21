EN | [中文](./README.cn.md)

# SmartPrompt

[![Gem Version](https://badge.fury.io/rb/smart_prompt.svg)](https://badge.fury.io/rb/smart_prompt)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

SmartPrompt is a powerful Ruby gem that provides an elegant domain-specific language (DSL) for building intelligent applications with Large Language Models (LLMs). It enables Ruby programs to seamlessly interact with various LLM providers while maintaining clean, composable, and highly customizable code architecture.

## 🚀 Key Features

### Multi-LLM Support
- **OpenAI API Compatible**: Full support for OpenAI GPT models and compatible APIs
- **Llama.cpp Integration**: Direct integration with local Llama.cpp servers  
- **Extensible Adapters**: Easy-to-extend adapter system for new LLM providers
- **Unified Interface**: Same API regardless of the underlying LLM provider

### Flexible Architecture
- **Worker-based Tasks**: Define reusable workers for specific AI tasks
- **Template System**: ERB-based prompt templates with parameter injection
- **Conversation Management**: Built-in conversation history and context management
- **Streaming Support**: Real-time response streaming for better user experience

### Advanced Features
- **Tool Calling**: Native support for function calling and tool integration
- **Retry Logic**: Robust error handling with configurable retry mechanisms
- **Embeddings**: Text embedding generation for semantic search and RAG applications
- **Configuration-driven**: YAML-based configuration for easy deployment management

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
# LLM configurations
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

# Model aliases
models:
  local/qwen3.5:
    use: local
    model: qwen3.5
  deepseekv3.2:
    use: SiliconFlow
    model: Pro/deepseek-ai/DeepSeek-V3.2

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

```ruby
SmartPrompt.define_worker :conversational_chat do
  use "deepseek"
  model "deepseek-chat"
  sys_msg("You are a helpful assistant that remembers conversation context.")
  prompt(params[:message], with_history: true)
  send_msg
end
```

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
```

### Core Components

- **Engine**: Central orchestrator managing configuration, adapters, and workers
- **Workers**: Reusable task definitions with embedded business logic
- **Conversation**: Context and message history management
- **Adapters**: LLM provider integrations (OpenAI, Llama.cpp, etc.)
- **Templates**: ERB-based prompt template system

## 🔧 Configuration Reference

### Adapter Configuration

```yaml
adapters:
  openai: "OpenAIAdapter"      # For OpenAI API
```

### LLM Configuration

```yaml
llms:
  model_name:
    adapter: "adapter_name"
    api_key: "your_api_key"     # Can use ENV['KEY_NAME']
    url: "https://api.url"
    model: "model_identifier"
    temperature: 0.7
    # Additional provider-specific options
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

## 🛣️ Roadmap

- [ ] Additional LLM provider adapters (Anthropic Claude, Google PaLM)
- [ ] Visual prompt builder and management interface
- [ ] Enhanced caching and performance optimizations
- [ ] Integration with vector databases for RAG applications
- [ ] Built-in evaluation and testing framework for prompts
- [ ] Distributed worker execution support

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
