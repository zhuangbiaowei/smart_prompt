#!/usr/bin/env ruby
# frozen_string_literal: true

# History Management Example Workers
# These examples demonstrate the new intelligent history management features
# introduced in the history-optimization feature.

require_relative "../lib/smart_prompt"

=begin
# ============================================================================
# Example 1: Explicit Session Management
# ============================================================================
# This example demonstrates how to explicitly manage sessions with unique IDs.
# Each session maintains its own isolated conversation history.

puts "\n=== Example 1: Explicit Session Management ==="

# Initialize engine
engine = SmartPrompt::Engine.new("config/anthropic_config.yml")

# Define a worker with explicit session management
SmartPrompt.define_worker :explicit_session_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  # Use a unique session ID for each conversation
  # This could be a user ID, conversation ID, or any unique identifier
  # session_id is passed via params and automatically used by the conversation

  sys_msg("You are a helpful AI assistant.")
  prompt(params[:message])
  send_msg
end

# Example usage: Multiple isolated conversations
puts "\nCreating two separate conversations..."

# Conversation 1 with Alice
response1 = engine.call_worker(:explicit_session_chat, {
  session_id: "user_alice",
  message: "My name is Alice and I love programming.",
  with_history: true,
})
puts "Alice: #{response1}"

# Conversation 2 with Bob
response2 = engine.call_worker(:explicit_session_chat, {
  session_id: "user_bob",
  message: "My name is Bob and I enjoy cooking.",
  with_history: true,
})
puts "Bob: #{response2}"

# Continue Alice's conversation - should remember her name
response3 = engine.call_worker(:explicit_session_chat, {
  session_id: "user_alice",
  message: "What did I say I love?",
  with_history: true,
})
puts "Alice (follow-up): #{response3}"

# Continue Bob's conversation - should remember his name
response4 = engine.call_worker(:explicit_session_chat, {
  session_id: "user_bob",
  message: "What did I say I enjoy?",
  with_history: true,
})
puts "Bob (follow-up): #{response4}"
=end

# ============================================================================
# Example 2: Different Context Strategies
# ============================================================================
# This example demonstrates the different context strategies available:
# - Sliding Window: Keeps most recent N messages
# - Relevance-Based: Selects semantically relevant messages
# - Summary-Based: Automatically compresses old messages
# - Hybrid: Adaptively combines strategies

puts "\n\n=== Example 2: Different Context Strategies ==="
engine = SmartPrompt::Engine.new("config/anthropic_config.yml")
# 2.1 Sliding Window Strategy
# Best for: Real-time chat, customer support, short conversations
SmartPrompt.define_worker :sliding_window_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  session_id = params[:session_id] || "sliding_window_session"

  # Configure session with sliding window strategy
  session_config = {
    max_messages: 3,        # Keep only last 10 messages
    max_tokens: 2000,        # Maximum 2000 tokens
    context_strategy: :sliding_window,
    preserve_system_messages: true,
  }

  sys_msg("You are a customer support assistant.", params)
  prompt(params[:message], with_history: true, session_id: session_id)

  # Apply session configuration
  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nSliding Window Strategy Example:"
puts "This strategy keeps only the most recent messages."

# Simulate a conversation with many messages
5.times do |i|
  response = engine.call_worker(:sliding_window_chat, {
    session_id: "sliding_demo",
    message: "This is message number #{i + 1}. Can you count?",
  })
  puts "Message #{i + 1} response: #{response[0..50]}..."
end

=begin
# 2.2 Relevance-Based Strategy
# Best for: Q&A systems, knowledge bases, context-aware assistants
SmartPrompt.define_worker :relevance_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  session_id = params[:session_id] || "relevance_session"

  # Configure session with relevance-based strategy
  session_config = {
    max_messages: 50,
    max_tokens: 4000,
    context_strategy: :relevance_based,
    preserve_system_messages: true,
  }

  sys_msg("You are a knowledgeable AI assistant.", params)
  prompt(params[:message], with_history: true, session_id: session_id)

  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nRelevance-Based Strategy Example:"
puts "This strategy selects semantically relevant messages."

# Example conversation with topic changes
topics = [
  "Tell me about Ruby programming.",
  "What about Python?",
  "Now explain JavaScript.",
  "Going back to Ruby, what are its best features?",
]

topics.each_with_index do |message, i|
  response = engine.call_worker(:relevance_chat, {
    session_id: "relevance_demo",
    message: message,
  })
  puts "Topic #{i + 1}: #{message}"
  puts "Response: #{response[0..80]}...\n"
end

# 2.3 Summary-Based Strategy
# Best for: Long conversations, documentation, extended dialogues
SmartPrompt.define_worker :summary_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  session_id = params[:session_id] || "summary_session"

  # Configure session with summary-based strategy
  session_config = {
    max_messages: 100,
    max_tokens: 8000,
    context_strategy: :summary_based,
    preserve_system_messages: true,
  }

  sys_msg("You are a thoughtful AI assistant for extended conversations.", params)
  prompt(params[:message], with_history: true, session_id: session_id)

  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nSummary-Based Strategy Example:"
puts "This strategy automatically compresses old messages into summaries."

# Simulate a long conversation
10.times do |i|
  response = engine.call_worker(:summary_chat, {
    session_id: "summary_demo",
    message: "Tell me fact number #{i + 1} about space exploration.",
  })
  puts "Fact #{i + 1} received (#{response.length} chars)"
end

# 2.4 Hybrid Strategy
# Best for: General-purpose applications, varied conversation types
SmartPrompt.define_worker :hybrid_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  session_id = params[:session_id] || "hybrid_session"

  # Configure session with hybrid strategy
  session_config = {
    max_messages: 75,
    max_tokens: 6000,
    context_strategy: :hybrid,
    preserve_system_messages: true,
  }

  sys_msg("You are an intelligent AI assistant that adapts to conversation context.", params)
  prompt(params[:message], with_history: true, session_id: session_id)

  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nHybrid Strategy Example:"
puts "This strategy adaptively combines multiple strategies."

response = engine.call_worker(:hybrid_chat, {
  session_id: "hybrid_demo",
  message: "Let's have a conversation that covers many topics.",
})
puts "Response: #{response[0..80]}..."

# ============================================================================
# Example 3: Session Operations (clear, export, search, stats, delete)
# ============================================================================
# This example demonstrates various session management operations.

puts "\n\n=== Example 3: Session Operations ==="

# Create a session with some messages
session_id = "operations_demo"
engine = SmartPrompt::Engine.new

# Add some messages
puts "\nAdding messages to session..."
engine.history_manager.add_message(session_id, {
  role: "system",
  content: "You are a helpful assistant.",
})
engine.history_manager.add_message(session_id, {
  role: "user",
  content: "Hello! My name is Alice.",
})
engine.history_manager.add_message(session_id, {
  role: "assistant",
  content: "Hello Alice! Nice to meet you.",
})
engine.history_manager.add_message(session_id, {
  role: "user",
  content: "Can you help me with Ruby programming?",
})
engine.history_manager.add_message(session_id, {
  role: "assistant",
  content: "Of course! I'd be happy to help with Ruby programming.",
})

# 3.1 Get Statistics
puts "\n--- Get Statistics ---"
stats = engine.history_manager.get_stats(session_id)
puts "Session Statistics:"
puts "  Message Count: #{stats[:message_count]}"
puts "  Total Tokens: #{stats[:total_tokens]}"
puts "  Created At: #{stats[:created_at]}"
puts "  Updated At: #{stats[:updated_at]}"

# 3.2 Search Messages
puts "\n--- Search Messages ---"
search_results = engine.history_manager.search_messages(session_id, "Ruby")
puts "Search results for 'Ruby': #{search_results.count} messages found"
search_results.each do |msg|
  puts "  [#{msg.role}]: #{msg.content[0..50]}..."
end

# 3.3 Export Session
puts "\n--- Export Session ---"
exported_data = engine.history_manager.export_session(session_id, format: :hash)
puts "Exported session data:"
puts "  ID: #{exported_data[:id]}"
puts "  Messages: #{exported_data[:messages].count}"
puts "  First message: #{exported_data[:messages].first[:content][0..50]}..."

# 3.4 Clear Session (keeping system messages)
puts "\n--- Clear Session ---"
puts "Messages before clear: #{engine.history_manager.get_stats(session_id)[:message_count]}"
engine.history_manager.clear_session(session_id, keep_system_messages: true)
puts "Messages after clear: #{engine.history_manager.get_stats(session_id)[:message_count]}"

# 3.5 Delete Session
puts "\n--- Delete Session ---"
puts "Session exists before delete: #{engine.history_manager.session_exists?(session_id)}"
engine.history_manager.delete_session(session_id)
puts "Session exists after delete: #{engine.history_manager.session_exists?(session_id)}"

# ============================================================================
# Example 4: Backward Compatibility
# ============================================================================
# This example demonstrates backward compatibility with the old API.

puts "\n\n=== Example 4: Backward Compatibility ==="

# Old-style worker definition (still works!)
SmartPrompt.define_worker :legacy_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  sys_msg("You are a helpful AI assistant.")

  # Old-style history usage - still works!
  prompt(params[:message], with_history: true)

  send_msg
end

puts "\nUsing legacy API (with_history: true)..."
response = engine.call_worker(:legacy_chat, {
  message: "Hello! This is using the old API.",
})
puts "Response: #{response[0..80]}..."

# The new system automatically creates a default session
# and maintains backward compatibility

# ============================================================================
# Example 5: Advanced - Multi-User Chat Application
# ============================================================================
# This example shows how to build a multi-user chat application
# with isolated sessions per user.

puts "\n\n=== Example 5: Multi-User Chat Application ==="

SmartPrompt.define_worker :multi_user_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  # Use user ID as session ID for isolation
  user_id = params[:user_id] || raise("user_id is required")
  session_id = "user_#{user_id}"

  # Configure per-user session
  session_config = {
    max_messages: 50,
    max_tokens: 3000,
    context_strategy: :sliding_window,
    preserve_system_messages: true,
  }

  user_name = params[:user_name] || "User"
  sys_msg("You are a personal AI assistant for #{user_name}.")
  prompt(params[:message], with_history: true, session_id: session_id)

  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nSimulating multi-user chat..."

# User 1
response1 = engine.call_worker(:multi_user_chat, {
  user_id: "001",
  user_name: "Alice",
  message: "Hi! I'm working on a Ruby project.",
})
puts "Alice: #{response1[0..60]}..."

# User 2
response2 = engine.call_worker(:multi_user_chat, {
  user_id: "002",
  user_name: "Bob",
  message: "Hello! I need help with Python.",
})
puts "Bob: #{response2[0..60]}..."

# User 1 continues (should remember Ruby context)
response3 = engine.call_worker(:multi_user_chat, {
  user_id: "001",
  user_name: "Alice",
  message: "What language was I asking about?",
})
puts "Alice (follow-up): #{response3[0..60]}..."

# ============================================================================
# Example 6: Monitoring and Debugging
# ============================================================================
# This example demonstrates how to monitor and debug the history system.

puts "\n\n=== Example 6: Monitoring and Debugging ==="

engine = SmartPrompt::Engine.new

# Get system-wide statistics
puts "\n--- System-Wide Statistics ---"
system_stats = engine.history_manager.get_stats
puts "Active Sessions: #{system_stats[:active_sessions]}"
puts "Total Messages: #{system_stats[:total_messages]}"
puts "Total Tokens: #{system_stats[:total_tokens]}"
puts "Cache Hit Rate: #{(system_stats[:cache_hit_rate] * 100).round(2)}%"
puts "Messages Added: #{system_stats[:messages_added]}"
puts "Context Retrievals: #{system_stats[:context_retrievals]}"

# Export metrics in Prometheus format
puts "\n--- Prometheus Metrics ---"
prometheus_metrics = engine.history_manager.export_metrics(format: :prometheus)
puts prometheus_metrics.lines.first(10).join

# List all active sessions
puts "\n--- Active Sessions ---"
session_ids = engine.history_manager.session_ids
puts "Total active sessions: #{session_ids.count}"
session_ids.first(5).each do |sid|
  puts "  - #{sid}"
end

# ============================================================================
# Example 7: Custom Configuration
# ============================================================================
# This example shows how to fine-tune session configuration for specific use cases.

puts "\n\n=== Example 7: Custom Configuration ==="

SmartPrompt.define_worker :custom_config_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"

  session_id = params[:session_id] || "custom_session"

  # Fine-tuned configuration for a code review assistant
  session_config = {
    max_messages: 100,
    max_tokens: 8000,
    context_strategy: :relevance_based,
    preserve_system_messages: true,
  }

  sys_msg("You are an expert code reviewer. Analyze code and provide constructive feedback.")
  prompt(params[:message], with_history: true, session_id: session_id)

  @engine.history_manager.get_session(session_id, session_config)

  send_msg
end

puts "\nCode review assistant with custom configuration..."
response = SmartPrompt.run_worker(:custom_config_chat, {
  session_id: "code_review_001",
  message: "Please review this Ruby code: def hello; puts 'world'; end",
})
puts "Review: #{response[0..100]}..."

# ============================================================================
# Example 8: Session Lifecycle Management
# ============================================================================
# This example demonstrates the complete lifecycle of a session.

puts "\n\n=== Example 8: Session Lifecycle Management ==="

engine = SmartPrompt::Engine.new
lifecycle_session_id = "lifecycle_demo"

# 1. Create session (implicitly through add_message)
puts "\n1. Creating session..."
engine.history_manager.add_message(lifecycle_session_id, {
  role: "system",
  content: "You are a helpful assistant.",
})
puts "   Session created: #{engine.history_manager.session_exists?(lifecycle_session_id)}"

# 2. Add messages
puts "\n2. Adding messages..."
3.times do |i|
  engine.history_manager.add_message(lifecycle_session_id, {
    role: "user",
    content: "Message #{i + 1}",
  })
end
stats = engine.history_manager.get_stats(lifecycle_session_id)
puts "   Messages in session: #{stats[:message_count]}"

# 3. Retrieve context
puts "\n3. Retrieving context..."
context = engine.history_manager.get_context(lifecycle_session_id)
puts "   Retrieved #{context.count} messages"

# 4. Export for backup
puts "\n4. Exporting session..."
backup = engine.history_manager.export_session(lifecycle_session_id, format: :json)
puts "   Exported #{backup.length} bytes"

# 5. Clear session
puts "\n5. Clearing session..."
engine.history_manager.clear_session(lifecycle_session_id)
stats = engine.history_manager.get_stats(lifecycle_session_id)
puts "   Messages after clear: #{stats[:message_count]}"

# 6. Delete session
puts "\n6. Deleting session..."
engine.history_manager.delete_session(lifecycle_session_id)
puts "   Session exists: #{engine.history_manager.session_exists?(lifecycle_session_id)}"

puts "\n\n=== All Examples Completed ==="
puts "These examples demonstrate the key features of the new history management system:"
puts "  ✓ Explicit session management with unique IDs"
puts "  ✓ Multiple context strategies (sliding window, relevance, summary, hybrid)"
puts "  ✓ Session operations (clear, export, search, stats, delete)"
puts "  ✓ Backward compatibility with existing API"
puts "  ✓ Multi-user applications with session isolation"
puts "  ✓ Monitoring and debugging capabilities"
puts "  ✓ Custom configuration for specific use cases"
puts "  ✓ Complete session lifecycle management"

=end
