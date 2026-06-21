#!/usr/bin/env ruby
# frozen_string_literal: true

require "./lib/smart_prompt"

# Example: Using Anthropic Claude with SmartPrompt
# This example demonstrates various features of the AnthropicAdapter

# Initialize the engine with Anthropic configuration
engine = SmartPrompt::Engine.new("config/anthropic_config.yml")

puts "=" * 60
puts "Anthropic Claude Examples with SmartPrompt"
puts "=" * 60

=begin
# Example 1: Basic Chat
puts "\n1. Basic Chat Example"
puts "-" * 60

SmartPrompt.define_worker :basic_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  sys_msg("You are a helpful AI assistant.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:basic_chat, {
  message: "What is the capital of France?",
})
puts "User: What is the capital of France?"
puts "DeepSeek: #{response}"

# Example 2: Multi-turn Conversation
puts "\n2. Multi-turn Conversation Example"
puts "-" * 60

SmartPrompt.define_worker :conversation do
  use "deepseek_anthropic"
  model "deepseek-chat"
  sys_msg("You are a knowledgeable history teacher.")
  prompt(params[:message], with_history: true)
  send_msg
end

response1 = engine.call_worker(:conversation, {  
  message: "Who was the first president of the United States?",
  with_history: true,
})
puts "User: Who was the first president of the United States?"
puts "Claude: #{response1}"

response2 = engine.call_worker(:conversation, {
  message: "What were his major accomplishments?",
  with_history: true,
})
puts "\nUser: What were his major accomplishments?"
puts "Claude: #{response2}"

# Example 3: Code Generation
puts "\n3. Code Generation Example"
puts "-" * 60

SmartPrompt.define_worker :code_generator do
  use "deepseek_anthropic"
  model "deepseek-chat"
  sys_msg("You are an expert programmer. Generate clean, well-documented code.")
  prompt("Write a Ruby function that #{params[:task]}")
  send_msg
end

code = engine.call_worker(:code_generator, {
  task: "calculates the factorial of a number using recursion",
})
puts "Task: Write a Ruby function that calculates the factorial of a number using recursion"
puts "Generated Code:\n#{code}"

# Example 4: Streaming Response
puts "\n4. Streaming Response Example"
puts "-" * 60

SmartPrompt.define_worker :streaming_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  sys_msg("You are a storyteller.")
  prompt(params[:message])
  send_msg
end

print "User: Tell me a short story about a brave knight.\n"
print "Claude (streaming): "

engine.call_worker_by_stream(:streaming_chat, {
  message: "Tell me a short story about a brave knight.",
}) do |chunk, bytesize|
  # Handle Anthropic streaming format
  if chunk.is_a?(Hash)
    if chunk["type"] == "content_block_delta"
      text = chunk.dig("delta", "text")
      print text if text
    end
  end
end

puts "\n"
=end

# Example 7: Tool Calling (Function Calling)
puts "\n7. Tool Calling Example"
puts "-" * 60

# Define tools
weather_tools = [
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
            description: "The city and state, e.g. San Francisco, CA",
          },
          unit: {
            type: "string",
            enum: ["celsius", "fahrenheit"],
            description: "The temperature unit",
          },
        },
        required: ["location"],
      },
    },
  },
]

SmartPrompt.define_worker :weather_assistant do
  use "deepseek_anthropic"
  model "deepseek-chat"
  sys_msg("You are a helpful weather assistant. Use the get_weather tool when users ask about weather.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:weather_assistant, {
  message: "What's the weather like in Tokyo?",
  tools: weather_tools,
})
puts "User: What's the weather like in Tokyo?"
puts "Claude: #{response}"

=begin

# Example 8: Image Analysis (Multimodal)
puts "\n8. Image Analysis Example (Multimodal)"
puts "-" * 60

SmartPrompt.define_worker :image_analyzer do
  use "claude"
  sys_msg("You are an expert at analyzing images and describing what you see.")
  prompt(params[:message])
  send_msg
end

# Using a public image URL
image_url = "https://upload.wikimedia.org/wikipedia/commons/thumb/3/3a/Cat03.jpg/1200px-Cat03.jpg"

response = engine.call_worker(:image_analyzer, {
  message: [
    { type: "text", text: "What do you see in this image? Describe it in detail." },
    { type: "image_url", image_url: image_url }
  ]
})
puts "User: [Sends image of a cat]"
puts "Claude: #{response}"

# Example 9: Different Models Comparison
puts "\n9. Different Models Comparison"
puts "-" * 60

question = "Explain quantum entanglement in simple terms."

# Using Claude 3.5 Sonnet
SmartPrompt.define_worker :sonnet_chat do
  use "claude"
  model "claude-3-5-sonnet-20241022"
  prompt(params[:message])
  send_msg
end

sonnet_response = engine.call_worker(:sonnet_chat, { message: question })
puts "Question: #{question}"
puts "\nClaude 3.5 Sonnet Response:"
puts sonnet_response[0..200] + "..."

# Using Claude 3.5 Haiku (faster)
SmartPrompt.define_worker :haiku_chat do
  use "claude_haiku"
  model "claude-3-5-haiku-20241022"
  prompt(params[:message])
  send_msg
end

haiku_response = engine.call_worker(:haiku_chat, { message: question })
puts "\nClaude 3.5 Haiku Response:"
puts haiku_response[0..200] + "..."

# Example 10: Error Handling
puts "\n10. Error Handling Example"
puts "-" * 60

begin
  # Try to use a non-existent model
  SmartPrompt.define_worker :error_test do
    use "claude"
    model "non-existent-model"
    prompt(params[:message])
    send_msg
  end

  engine.call_worker(:error_test, { message: "Hello" })
rescue SmartPrompt::LLMAPIError => e
  puts "Caught API Error: #{e.message}"
  puts "Error handling works correctly!"
end

puts "\n" + "=" * 60
puts "All examples completed!"
puts "=" * 60
=end
