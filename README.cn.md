# SmartPrompt

SmartPrompt 是一个强大的 Ruby gem，提供了一种领域特定语言（DSL），使其他 Ruby 程序能够更加方便、自然地调用各种大型语言模型（LLM）的能力。

## 主要特性

- 灵活的任务组合：以特定服务提供商 + 特定 LLM + 特定 prompt 的方式组合各种任务
- 子任务嵌套：支持以 DSL 形式组合调用其他子任务
- 性能优化：在保证质量的同时，提供性能最优或成本最低的解决方案

## 安装

将 gem 安装并添加到应用程序的 Gemfile 中，执行以下命令：

```
$ bundle add smart_prompt
```

如果不使用 bundler 来管理依赖，可以通过执行以下命令来安装 gem：

```
$ gem install smart_prompt
```

## 用法

以下是一些基本用法示例：

### 配置文件

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

### 基本使用

```
require 'smart_prompt'
engine = SmartPrompt::Engine.new('./config/llm_config.yml')
result = engine.call_worker(:daily_report, {location: "Shanghai"}) 
puts result
```

### workers/daily_report.rb

```
SmartPrompt.define_worker :daily_report do
    use "ollama"
    model "gemma2"
    system "You are a helpful report writer."
    weather = call_worker(:weather_summary, { location: params[:location], date: "today" })
    prompt :daily_report, { weather: weather, location: params[:location] }
    send_msg
end
```

### workers/weather_summary.rb

```
SmartPrompt.define_worker :weather_summary do
  use "ollama"
  model "gemma2"
  sys_msg "You are a helpful weather assistant."
  prompt :weather, { location: params[:location], date: params[:date] }
  weather_info = send_msg
  prompt :summarize, { text: weather_info }
  send_msg
end
```

### templates/daily_report.erb

```
Please create a brief daily report for <%= location %> based on the following weather information:

<%= weather %>

The report should include:
1. A summary of the weather
2. Any notable events or conditions
3. Recommendations for residents
```
### templates/weather.erb

```
What's the weather like in <%= location %> <%= date %>? Please provide a brief description including temperature and general conditions.
```

### templates/summarize.erb

```
Please summarize the following text in one sentence:

<%= text %>
```