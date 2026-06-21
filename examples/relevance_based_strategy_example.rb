#!/usr/bin/env ruby
# Example demonstrating the RelevanceBasedStrategy

require_relative '../lib/smart_prompt'

# Create a session with some conversation history
session = SmartPrompt::Session.new("demo_session", {})

# Add a diverse set of messages
session.add_message(role: "system", content: "You are a helpful AI assistant")
session.add_message(role: "user", content: "Tell me about machine learning")
session.add_message(role: "assistant", content: "Machine learning is a subset of artificial intelligence that enables systems to learn from data")
session.add_message(role: "user", content: "What are your favorite animals?")
session.add_message(role: "assistant", content: "I don't have personal preferences, but many people love cats and dogs")
session.add_message(role: "user", content: "How does deep learning work?")
session.add_message(role: "assistant", content: "Deep learning uses neural networks with multiple layers to learn hierarchical representations")
session.add_message(role: "user", content: "Tell me a joke")
session.add_message(role: "assistant", content: "Why did the programmer quit? Because they didn't get arrays!")
session.add_message(role: "user", content: "What is supervised learning?")
session.add_message(role: "assistant", content: "Supervised learning is when you train a model with labeled data")

puts "=" * 80
puts "RelevanceBasedStrategy Example"
puts "=" * 80
puts

# Create the strategy
strategy = SmartPrompt::RelevanceBasedStrategy.new(
  top_k: 5,
  recency_weight: 0.3,
  relevance_weight: 0.7
)

# Current message is about neural networks
current_message = SmartPrompt::Message.new(
  role: "user",
  content: "Can you explain more about neural networks and how they relate to machine learning?"
)

puts "Current message: #{current_message.content}"
puts
puts "Total messages in session: #{session.message_count}"
puts

# Select relevant messages
messages = session.get_messages
selected = strategy.select_messages(messages, nil, current_message)

puts "Selected #{selected.length} most relevant messages:"
puts "-" * 80
selected.each_with_index do |msg, idx|
  puts "#{idx + 1}. [#{msg.role}] #{msg.content}"
end
puts

# Demonstrate with token limit
puts "=" * 80
puts "With Token Limit (100 tokens)"
puts "=" * 80
selected_limited = strategy.select_messages(messages, 100, current_message)
total_tokens = selected_limited.sum { |m| m.token_count || 0 }

puts "Selected #{selected_limited.length} messages (#{total_tokens} tokens):"
puts "-" * 80
selected_limited.each_with_index do |msg, idx|
  tokens = msg.token_count || 0
  puts "#{idx + 1}. [#{msg.role}] (#{tokens} tokens) #{msg.content[0..60]}..."
end
puts

# Show compression recommendation
puts "=" * 80
puts "Compression Recommendation"
puts "=" * 80
should_compress = strategy.should_compress?(session)
puts "Should compress? #{should_compress}"
puts "Reason: Session has #{session.message_count} messages, threshold is #{5 * 3} messages"
puts

puts "=" * 80
puts "Strategy Configuration"
puts "=" * 80
puts "Top-k: 5"
puts "Recency weight: 0.3"
puts "Relevance weight: 0.7"
puts "Embedding service: Not configured (using keyword similarity)"
puts "=" * 80
