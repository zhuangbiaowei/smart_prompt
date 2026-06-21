#!/usr/bin/env ruby
# frozen_string_literal: true

require './lib/smart_prompt'

# Example: Basic Chat with Anthropic Claude
# This example demonstrates simple text-based conversations with Claude

puts "=" * 60
puts "Anthropic Claude - Basic Chat Example"
puts "=" * 60

# Initialize the engine with Anthropic configuration
engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

# Example 1: Simple Question-Answer
puts "\n1. Simple Question-Answer"
puts "-" * 60

SmartPrompt.define_worker :simple_chat do
  use "claude"
  sys_msg("You are a helpful AI assistant.")
  prompt(params[:message])
  send_msg
end

response = engine.call_worker(:simple_chat, {
  message: "What is the capital of France?"
})
puts "User: What is the capital of France?"
puts "Claude: #{response}\n"

# Example 2: Multi-turn Conversation with History
puts "\n2. Multi-turn Conversation"
puts "-" * 60

SmartPrompt.define_worker :conversation do
  use "claude"
  sys_msg("You are a knowledgeable history teacher.")
  prompt(params[:message], with_history: true)
  send_msg
end

response1 = engine.call_worker(:conversation, {
  message: "Who was the first president of the United States?"
})
puts "User: Who was the first president of the United States?"
puts "Claude: #{response1}\n"

response2 = engine.call_worker(:conversation, {
  message: "What were his major accomplishments?"
})
puts "User: What were his major accomplishments?"
puts "Claude: #{response2}\n"

# Example 3: Using Different Models
puts "\n3. Comparing Different Claude Models"
puts "-" * 60

question = "Explain quantum entanglement in one sentence."

# Claude 3.5 Sonnet (balanced)
SmartPrompt.define_worker :sonnet_chat do
  use "claude"
  model "claude-3-5-sonnet-20241022"
  prompt(params[:message])
  send_msg
end

sonnet_response = engine.call_worker(:sonnet_chat, { message: question })
puts "Question: #{question}"
puts "\nClaude 3.5 Sonnet: #{sonnet_response}\n"

# Claude 3.5 Haiku (faster)
SmartPrompt.define_worker :haiku_chat do
  use "claude_haiku"
  model "claude-3-5-haiku-20241022"
  prompt(params[:message])
  send_msg
end

haiku_response = engine.call_worker(:haiku_chat, { message: question })
puts "Claude 3.5 Haiku: #{haiku_response}\n"

# Example 4: Temperature Control
puts "\n4. Temperature Control for Creativity"
puts "-" * 60

# Creative response (high temperature)
SmartPrompt.define_worker :creative_chat do
  use "claude_creative"  # temperature: 0.9
  sys_msg("You are a creative writer.")
  prompt("Write a creative tagline for a coffee shop.")
  send_msg
end

creative = engine.call_worker(:creative_chat, {})
puts "Creative (temp=0.9): #{creative}\n"

# Precise response (low temperature)
SmartPrompt.define_worker :precise_chat do
  use "claude_precise"  # temperature: 0.3
  sys_msg("You are a precise analyst.")
  prompt("Write a tagline for a coffee shop.")
  send_msg
end

precise = engine.call_worker(:precise_chat, {})
puts "Precise (temp=0.3): #{precise}\n"

# Example 5: System Message Variations
puts "\n5. System Message Variations"
puts "-" * 60

question = "Should I invest in cryptocurrency?"

# As a financial advisor
SmartPrompt.define_worker :advisor_chat do
  use "claude"
  sys_msg("You are a conservative financial advisor.")
  prompt(params[:message])
  send_msg
end

advisor_response = engine.call_worker(:advisor_chat, { message: question })
puts "As Financial Advisor:"
puts advisor_response[0..150] + "...\n"

# As a tech enthusiast
SmartPrompt.define_worker :enthusiast_chat do
  use "claude"
  sys_msg("You are an enthusiastic technology advocate.")
  prompt(params[:message])
  send_msg
end

enthusiast_response = engine.call_worker(:enthusiast_chat, { message: question })
puts "\nAs Tech Enthusiast:"
puts enthusiast_response[0..150] + "...\n"

puts "\n" + "=" * 60
puts "Basic chat examples completed!"
puts "=" * 60
