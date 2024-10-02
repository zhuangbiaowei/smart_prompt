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

### Basic usage

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