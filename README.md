EN | [中文](./README.cn.md)

# SmartPrompt

SmartPrompt is a powerful Ruby gem that provides a domain-specific language (DSL), enabling other Ruby programs to conveniently and naturally call upon the capabilities of various large language models (LLMs).

## Key Features

- Flexible task composition: Combine various tasks using specific service providers + specific LLMs + specific prompts
- Nested subtasks: Support for composing and calling other subtasks in DSL form
- Performance optimization: Provide performance-optimal or cost-effective solutions while ensuring quality

## Installation

To install the gem and add it to your application's Gemfile, execute the following command:

```
$ bundle add smart_prompt
```

If you don't use a bundler to manage dependencies, you can install the gem by executing the following command:

```
$ gem install smart_prompt
```

## Usage

The following are some examples of basic usage:

### Basic usage

```
require 'smart_prompt'
engine = SmartPrompt::Engine.new('./config/llm_config.yml')
result = engine.call_worker(:daily_report, {location: "Shanghai"}) 
puts result
```

### llm_config.yml

```
adapters:
  openai: OpenAIAdapter
  ollama: OllamaAdapter
llms:
  siliconflow:
    adapter: openai
    url: https://api.siliconflow.cn/v1/
    api_key: ENV["APIKey"]
    default_model: Qwen/Qwen2.5-7B-Instruct
  llamacpp:
    adapter: openai
    url: http://localhost:8080/    
  ollama:
    adapter: ollama
    url: http://localhost:11434/
    default_model: qwen2.5
default_llm: siliconflow
worker_path: "./workers"
template_path: "./templates"
```