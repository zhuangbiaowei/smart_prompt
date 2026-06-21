#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/smart_prompt'

# Example: Streaming Responses with Anthropic Claude
# This example demonstrates how to use Claude's streaming capabilities

puts "=" * 60
puts "Anthropic Claude - Streaming Response Example"
puts "=" * 60

# Initialize the engine with Anthropic configuration
engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

# Example 1: Basic Streaming
puts "\n1. Basic Streaming Response"
puts "-" * 60

SmartPrompt.define_worker :streaming_chat do
  use "claude"
  sys_msg("You are a helpful assistant.")
  prompt(params[:message])
  send_msg
end

print "User: Tell me a short story about a brave knight.\n"
print "Claude (streaming): "

engine.call_worker_by_stream(:streaming_chat, {
  message: "Tell me a short story about a brave knight."
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

# Example 2: Streaming with Different Event Types
puts "\n2. Streaming with Event Type Handling"
puts "-" * 60

SmartPrompt.define_worker :detailed_streaming do
  use "claude"
  sys_msg("You are a knowledgeable teacher.")
  prompt(params[:message])
  send_msg
end

print "User: Explain how photosynthesis works.\n"
print "Claude: "

message_started = false
content_started = false

engine.call_worker_by_stream(:detailed_streaming, {
  message: "Explain how photosynthesis works in 3-4 sentences."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash)
    case chunk["type"]
    when "message_start"
      message_started = true
      # Message metadata available in chunk["message"]
    when "content_block_start"
      content_started = true
      # Content block started
    when "content_block_delta"
      text = chunk.dig("delta", "text")
      print text if text
    when "content_block_stop"
      # Content block finished
    when "message_delta"
      # Message metadata update (e.g., stop_reason)
    when "message_stop"
      # Message completely finished
    end
  end
end

puts "\n"

# Example 3: Streaming Long-form Content
puts "\n3. Streaming Long-form Content"
puts "-" * 60

SmartPrompt.define_worker :long_form_streaming do
  use "claude"
  sys_msg("You are a creative writer who writes engaging stories.")
  prompt(params[:message])
  send_msg
end

print "User: Write a detailed story about a robot learning to paint.\n"
print "Claude: "

total_chars = 0

engine.call_worker_by_stream(:long_form_streaming, {
  message: "Write a detailed story (about 200 words) about a robot learning to paint."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    if text
      print text
      total_chars += text.length
    end
  end
end

puts "\n\n[Total characters streamed: #{total_chars}]"

# Example 4: Streaming with Progress Indicator
puts "\n4. Streaming with Progress Indicator"
puts "-" * 60

SmartPrompt.define_worker :progress_streaming do
  use "claude"
  sys_msg("You are a helpful coding assistant.")
  prompt(params[:message])
  send_msg
end

print "User: Write a Python function to calculate Fibonacci numbers.\n"
print "Claude: "

char_count = 0
last_dot_time = Time.now

engine.call_worker_by_stream(:progress_streaming, {
  message: "Write a Python function to calculate Fibonacci numbers with comments."
}) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    if text
      print text
      char_count += text.length
      
      # Print a progress indicator every 50 characters
      if char_count % 50 == 0 && Time.now - last_dot_time > 0.5
        # This is just for demonstration
        last_dot_time = Time.now
      end
    end
  end
end

puts "\n"

# Example 5: Streaming with Error Handling
puts "\n5. Streaming with Error Handling"
puts "-" * 60

SmartPrompt.define_worker :safe_streaming do
  use "claude"
  sys_msg("You are a helpful assistant.")
  prompt(params[:message])
  send_msg
end

print "User: What are the benefits of exercise?\n"
print "Claude: "

begin
  engine.call_worker_by_stream(:safe_streaming, {
    message: "What are the benefits of exercise? List 5 benefits."
  }) do |chunk, bytesize|
    if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
      text = chunk.dig("delta", "text")
      print text if text
    end
  end
  puts "\n[Stream completed successfully]"
rescue SmartPrompt::LLMAPIError => e
  puts "\n[Error during streaming: #{e.message}]"
rescue StandardError => e
  puts "\n[Unexpected error: #{e.message}]"
end

puts ""

# Example 6: Streaming vs Non-Streaming Comparison
puts "\n6. Streaming vs Non-Streaming Comparison"
puts "-" * 60

question = "Explain the theory of relativity in simple terms."

# Non-streaming (traditional)
puts "Non-streaming mode:"
print "User: #{question}\n"
print "Claude: "

start_time = Time.now

SmartPrompt.define_worker :non_streaming_chat do
  use "claude"
  sys_msg("You are a physics teacher.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:non_streaming_chat, { message: question })
end_time = Time.now

puts response
puts "[Response received in #{(end_time - start_time).round(2)} seconds]\n"

# Streaming mode
puts "\nStreaming mode:"
print "User: #{question}\n"
print "Claude: "

start_time = Time.now
first_chunk_time = nil

SmartPrompt.define_worker :streaming_comparison do
  use "claude"
  sys_msg("You are a physics teacher.")
  prompt(params[:message])
  send_msg
end

engine.call_worker_by_stream(:streaming_comparison, { message: question }) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    first_chunk_time ||= Time.now
    text = chunk.dig("delta", "text")
    print text if text
  end
end

end_time = Time.now

puts "\n[First chunk in #{(first_chunk_time - start_time).round(2)} seconds]"
puts "[Total time: #{(end_time - start_time).round(2)} seconds]\n"

# Example 7: Streaming with Different Models
puts "\n7. Streaming with Different Claude Models"
puts "-" * 60

question = "What is machine learning?"

# Claude 3.5 Sonnet
puts "Claude 3.5 Sonnet (streaming):"
print "User: #{question}\n"
print "Claude: "

SmartPrompt.define_worker :sonnet_streaming do
  use "claude"
  model "claude-3-5-sonnet-20241022"
  prompt(params[:message])
  send_msg
end

engine.call_worker_by_stream(:sonnet_streaming, { message: question }) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    print text if text
  end
end

puts "\n"

# Claude 3.5 Haiku (faster)
puts "\nClaude 3.5 Haiku (streaming):"
print "User: #{question}\n"
print "Claude: "

SmartPrompt.define_worker :haiku_streaming do
  use "claude_haiku"
  model "claude-3-5-haiku-20241022"
  prompt(params[:message])
  send_msg
end

engine.call_worker_by_stream(:haiku_streaming, { message: question }) do |chunk, bytesize|
  if chunk.is_a?(Hash) && chunk["type"] == "content_block_delta"
    text = chunk.dig("delta", "text")
    print text if text
  end
end

puts "\n"

# Example 8: Streaming Best Practices
puts "\n8. Streaming Best Practices"
puts "-" * 60

puts "Best Practices for Streaming with Claude:"
puts "1. Use streaming for long-form content to improve perceived latency"
puts "2. Handle different event types appropriately:"
puts "   - message_start: Initialize UI/state"
puts "   - content_block_delta: Display incremental text"
puts "   - message_stop: Finalize and clean up"
puts "3. Implement proper error handling for network issues"
puts "4. Consider buffering small chunks for smoother display"
puts "5. Show loading indicators before first chunk arrives"
puts "6. Use streaming for better user experience in chat applications"
puts "7. Non-streaming is better for short responses or batch processing"
puts "8. Test streaming behavior with different network conditions"
puts "9. Implement timeout handling for stalled streams"
puts "10. Consider token usage - streaming doesn't reduce costs\n"

puts "\n" + "=" * 60
puts "Streaming examples completed!"
puts "=" * 60
puts "\nNote: Streaming provides a better user experience by showing"
puts "responses as they're generated, reducing perceived latency."
puts "The total time and token usage is similar to non-streaming mode."
