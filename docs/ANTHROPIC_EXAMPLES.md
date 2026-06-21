# Anthropic Claude Examples for SmartPrompt

This document provides comprehensive examples for using Anthropic's Claude models with SmartPrompt. Claude offers powerful capabilities including advanced reasoning, multimodal understanding (text + images), tool calling, and streaming responses.

## Table of Contents

1. [Setup and Configuration](#setup-and-configuration)
2. [Basic Chat Examples](#basic-chat-examples)
3. [Multimodal Examples (Vision)](#multimodal-examples-vision)
4. [Tool Calling Examples](#tool-calling-examples)
5. [Streaming Response Examples](#streaming-response-examples)
6. [Advanced Usage](#advanced-usage)
7. [Best Practices](#best-practices)

## Setup and Configuration

### 1. Install Dependencies

Ensure you have the `anthropic` gem installed:

```ruby
gem 'anthropic', '~> 1.14'
```

### 2. Set API Key

Set your Anthropic API key as an environment variable:

```bash
export ANTHROPIC_API_KEY='your-api-key-here'
```

### 3. Configure SmartPrompt

Create or update `config/anthropic_config.yml`:

```yaml
adapters:
  anthropic: "AnthropicAdapter"

llms:
  claude:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-5-sonnet-20241022"
    temperature: 0.7
    max_tokens: 4096

  claude_haiku:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-5-haiku-20241022"
    temperature: 0.7
    max_tokens: 4096

  claude_opus:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    model: "claude-3-opus-20240229"
    temperature: 0.7
    max_tokens: 4096
```

## Basic Chat Examples

### Simple Question-Answer

```ruby
require 'smart_prompt'

engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

SmartPrompt.define_worker :simple_chat do
  use "claude"
  sys_msg("You are a helpful AI assistant.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:simple_chat, {
  message: "What is the capital of France?"
})
puts response
```

**Run the example:**
```bash
ruby examples/anthropic_basic_chat.rb
```

### Multi-turn Conversation

```ruby
SmartPrompt.define_worker :conversation do
  use "claude"
  sys_msg("You are a knowledgeable history teacher.")
  prompt(params[:message], with_history: true)
  send_msg
end

# First message
response1 = engine.call_worker(:conversation, {
  message: "Who was the first president of the United States?"
})

# Follow-up message (maintains context)
response2 = engine.call_worker(:conversation, {
  message: "What were his major accomplishments?"
})
```

### Using Different Models

```ruby
# Claude 3.5 Sonnet - Best balance of intelligence and speed
SmartPrompt.define_worker :sonnet_chat do
  use "claude"
  model "claude-3-5-sonnet-20241022"
  prompt(params[:message])
  send_msg
end

# Claude 3.5 Haiku - Fastest, most cost-effective
SmartPrompt.define_worker :haiku_chat do
  use "claude_haiku"
  model "claude-3-5-haiku-20241022"
  prompt(params[:message])
  send_msg
end

# Claude 3 Opus - Highest quality for complex tasks
SmartPrompt.define_worker :opus_chat do
  use "claude_opus"
  model "claude-3-opus-20240229"
  prompt(params[:message])
  send_msg
end
```

### Temperature Control

```ruby
# Creative writing (high temperature)
SmartPrompt.define_worker :creative_chat do
  use "claude_creative"  # temperature: 0.9
  sys_msg("You are a creative writer.")
  prompt("Write a creative tagline for a coffee shop.")
  send_msg
end

# Precise analysis (low temperature)
SmartPrompt.define_worker :precise_chat do
  use "claude_precise"  # temperature: 0.3
  sys_msg("You are a precise analyst.")
  prompt("Analyze this data and provide key insights.")
  send_msg
end
```

## Multimodal Examples (Vision)

Claude can analyze images alongside text. Supported formats: JPEG, PNG, GIF, WebP (up to 5MB).

### Analyze Image from URL

```ruby
SmartPrompt.define_worker :image_analyzer do
  use "claude"
  sys_msg("You are an expert at analyzing images.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:image_analyzer, {
  message: [
    { type: "text", text: "What do you see in this image?" },
    { type: "image_url", image_url: "https://example.com/image.jpg" }
  ]
})
```

**Run the example:**
```bash
ruby examples/anthropic_multimodal.rb
```

### Analyze Local Image (Base64)

```ruby
require 'base64'

# Read and encode image
image_data = File.binread("./path/to/image.jpg")
base64_image = Base64.strict_encode64(image_data)
data_url = "data:image/jpeg;base64,#{base64_image}"

response = engine.call_worker(:image_analyzer, {
  message: [
    { type: "text", text: "Describe this image in detail." },
    { type: "image_url", image_url: data_url }
  ]
})
```

### Compare Multiple Images

```ruby
response = engine.call_worker(:image_analyzer, {
  message: [
    { type: "text", text: "Compare these two images." },
    { type: "image_url", image_url: "https://example.com/image1.jpg" },
    { type: "image_url", image_url: "https://example.com/image2.jpg" }
  ]
})
```

### OCR and Text Extraction

```ruby
SmartPrompt.define_worker :ocr_extractor do
  use "claude"
  sys_msg("You are an expert at reading text from images.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:ocr_extractor, {
  message: [
    { type: "text", text: "Extract all text from this image." },
    { type: "image_url", image_url: "https://example.com/document.jpg" }
  ]
})
```

### Product Image Analysis

```ruby
SmartPrompt.define_worker :product_analyzer do
  use "claude"
  sys_msg("You are a product analyst for e-commerce.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:product_analyzer, {
  message: [
    { type: "text", text: "Analyze this product image and provide:\n1. Product description\n2. Key features\n3. Suggested title" },
    { type: "image_url", image_url: "https://example.com/product.jpg" }
  ]
})
```

## Tool Calling Examples

Claude can use external tools/functions to perform actions or retrieve information.

### Simple Weather Tool

```ruby
weather_tool = [
  {
    type: "function",
    function: {
      name: "get_weather",
      description: "Get the current weather for a location",
      parameters: {
        type: "object",
        properties: {
          location: {
            type: "string",
            description: "The city and state, e.g. San Francisco, CA"
          },
          unit: {
            type: "string",
            enum: ["celsius", "fahrenheit"],
            description: "Temperature unit"
          }
        },
        required: ["location"]
      }
    }
  }
]

SmartPrompt.define_worker :weather_assistant do
  use "claude"
  sys_msg("You are a weather assistant. Use the get_weather tool.")
  prompt(params[:message])
  params.merge(tools: weather_tool)
  send_msg
end

response = engine.call_worker(:weather_assistant, {
  message: "What's the weather in Tokyo?"
})
```

**Run the example:**
```bash
ruby examples/anthropic_tool_calling.rb
```

### Multiple Calculator Tools

```ruby
calculator_tools = [
  {
    type: "function",
    function: {
      name: "add",
      description: "Add two numbers",
      parameters: {
        type: "object",
        properties: {
          a: { type: "number" },
          b: { type: "number" }
        },
        required: ["a", "b"]
      }
    }
  },
  {
    type: "function",
    function: {
      name: "multiply",
      description: "Multiply two numbers",
      parameters: {
        type: "object",
        properties: {
          a: { type: "number" },
          b: { type: "number" }
        },
        required: ["a", "b"]
      }
    }
  }
]

SmartPrompt.define_worker :calculator do
  use "claude"
  sys_msg("You are a calculator assistant.")
  prompt(params[:message])
  params.merge(tools: calculator_tools)
  send_msg
end
```

### Database Query Tool

```ruby
database_tool = [
  {
    type: "function",
    function: {
      name: "query_database",
      description: "Query the customer database",
      parameters: {
        type: "object",
        properties: {
          query_type: {
            type: "string",
            enum: ["customer_info", "order_history", "product_details"]
          },
          customer_id: { type: "string" }
        },
        required: ["query_type"]
      }
    }
  }
]
```

### Complex Tool with Nested Parameters

```ruby
search_tool = [
  {
    type: "function",
    function: {
      name: "search_products",
      description: "Search products with filters",
      parameters: {
        type: "object",
        properties: {
          query: { type: "string" },
          filters: {
            type: "object",
            properties: {
              category: { type: "string" },
              price_range: {
                type: "object",
                properties: {
                  min: { type: "number" },
                  max: { type: "number" }
                }
              },
              in_stock: { type: "boolean" }
            }
          },
          sort_by: {
            type: "string",
            enum: ["price_asc", "price_desc", "popularity"]
          }
        },
        required: ["query"]
      }
    }
  }
]
```

## Streaming Response Examples

Streaming provides better user experience by showing responses as they're generated.

### Basic Streaming

```ruby
SmartPrompt.define_worker :streaming_chat do
  use "claude"
  sys_msg("You are a helpful assistant.")
  prompt(params[:message])
  send_msg
end

engine.call_worker_by_stream(:streaming_chat, {
  message: "Tell me a story about a brave knight."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    print text if text
  end
end
```

**Run the example:**
```bash
ruby examples/anthropic_streaming.rb
```

### Handling Different Event Types

```ruby
engine.call_worker_by_stream(:streaming_chat, {
  message: "Explain photosynthesis."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash)
    case chunk["type"]
    when "message_start"
      # Message started
      puts "[Starting response...]"
    when "content_block_start"
      # Content block started
    when "content_block_delta"
      # Incremental text
      text = chunk.dig("delta", "text")
      print text if text
    when "content_block_stop"
      # Content block finished
    when "message_stop"
      # Message complete
      puts "\n[Response complete]"
    end
  end
end
```

### Streaming with Progress Tracking

```ruby
char_count = 0

engine.call_worker_by_stream(:streaming_chat, {
  message: "Write a Python function for Fibonacci."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    if text
      print text
      char_count += text.length
    end
  end
end

puts "\n[Total characters: #{char_count}]"
```

### Streaming with Error Handling

```ruby
begin
  engine.call_worker_by_stream(:streaming_chat, {
    message: "What are the benefits of exercise?"
  }) do |chunk, bytesize|
    if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
      text = chunk.dig("delta", "text")
      print text if text
    end
  end
  puts "\n[Stream completed successfully]"
rescue SmartPrompt::LLMAPIError => e
  puts "\n[Error: #{e.message}]"
end
```

## Advanced Usage

### Custom Endpoint (Proxy or Private Deployment)

```yaml
llms:
  claude_custom:
    adapter: "anthropic"
    api_key: ENV["ANTHROPIC_API_KEY"]
    url: "https://your-custom-endpoint.com"
    model: "claude-3-5-sonnet-20241022"
```

### Combining Multimodal and Tool Calling

```ruby
tools = [
  {
    type: "function",
    function: {
      name: "identify_object",
      description: "Identify objects in the image",
      parameters: {
        type: "object",
        properties: {
          object_name: { type: "string" }
        },
        required: ["object_name"]
      }
    }
  }
]

SmartPrompt.define_worker :multimodal_tools do
  use "claude"
  sys_msg("You can analyze images and use tools.")
  prompt(params[:message])
  params.merge(tools: tools)
  send_msg
end

response = engine.call_worker(:multimodal_tools, {
  message: [
    { type: "text", text: "What objects do you see? Use the identify_object tool." },
    { type: "image_url", image_url: "https://example.com/scene.jpg" }
  ]
})
```

### Conversation with Mixed Content

```ruby
SmartPrompt.define_worker :mixed_conversation do
  use "cla