#!/usr/bin/env ruby
# Example demonstrating the monitoring and logging features of HistoryManager

require_relative '../lib/smart_prompt'
require 'logger'

# Set up logger with INFO level
SmartPrompt.logger = Logger.new($stdout)
SmartPrompt.logger.level = Logger::INFO
SmartPrompt.logger.formatter = proc do |severity, datetime, progname, msg|
  "[#{datetime.strftime('%H:%M:%S')}] #{severity}: #{msg}\n"
end

puts "=" * 80
puts "History Manager Monitoring Example"
puts "=" * 80
puts

# Create a HistoryManager with monitoring enabled
config = {
  cache_size: 5,
  session_defaults: {
    max_messages: 10,
    max_tokens: 1000
  },
  persistence: {
    enabled: true,
    storage_path: "./history_data_example",
    async: false
  },
  monitoring: {
    enabled: true,
    log_level: :info
  }
}

manager = SmartPrompt::HistoryManager.new(config)

puts "\n--- Creating Sessions and Adding Messages ---\n"

# Create first session
manager.add_message("user_123", { role: "system", content: "You are a helpful assistant." })
manager.add_message("user_123", { role: "user", content: "What is machine learning?" })
manager.add_message("user_123", { role: "assistant", content: "Machine learning is a subset of AI..." })

# Create second session
manager.add_message("user_456", { role: "user", content: "Hello!" })
manager.add_message("user_456", { role: "assistant", content: "Hi! How can I help you?" })

puts "\n--- Getting Session Statistics ---\n"

# Get statistics for a specific session
session_stats = manager.get_stats("user_123")
puts "Session user_123 statistics:"
puts "  Messages: #{session_stats[:message_count]}"
puts "  Tokens: #{session_stats[:total_tokens]}"
puts "  Created: #{session_stats[:created_at]}"
puts

# Get system-wide statistics
system_stats = manager.get_stats
puts "System-wide statistics:"
puts "  Active sessions: #{system_stats[:active_sessions]}"
puts "  Total messages: #{system_stats[:total_messages]}"
puts "  Total tokens: #{system_stats[:total_tokens]}"
puts "  Messages per session (avg): #{system_stats[:messages_per_session_avg].round(2)}"
puts "  Tokens per message (avg): #{system_stats[:tokens_per_message_avg].round(2)}"
puts "  Cache hits: #{system_stats[:cache_hits]}"
puts "  Cache misses: #{system_stats[:cache_misses]}"
puts "  Cache hit rate: #{(system_stats[:cache_hit_rate] * 100).round(2)}%"
puts

puts "\n--- Exporting Metrics ---\n"

# Export metrics in different formats
puts "Prometheus format (first 10 lines):"
prometheus_metrics = manager.export_metrics(format: :prometheus)
puts prometheus_metrics.lines.first(10).join

puts "\nJSON format:"
json_metrics = manager.export_metrics(format: :json)
require 'json'
metrics_hash = JSON.parse(json_metrics)
puts JSON.pretty_generate(metrics_hash.slice(
  'active_sessions', 
  'total_messages', 
  'cache_hit_rate',
  'messages_per_session_avg'
))

puts "\n--- Retrieving Context ---\n"

# Retrieve context with token limit
context = manager.get_context("user_123", 500)
puts "Retrieved #{context.count} messages from user_123 (within 500 token limit)"

puts "\n--- Searching Messages ---\n"

# Search for messages
results = manager.search_messages("user_123", "machine learning")
puts "Found #{results.count} messages containing 'machine learning'"

puts "\n--- Clearing Session ---\n"

# Clear a session (keeping system messages)
manager.clear_session("user_456", keep_system_messages: true)

puts "\n--- Final Statistics ---\n"

final_stats = manager.get_stats
puts "Final system statistics:"
puts "  Active sessions: #{final_stats[:active_sessions]}"
puts "  Total messages: #{final_stats[:total_messages]}"
puts "  Sessions created: #{final_stats[:sessions_created]}"
puts "  Sessions deleted: #{final_stats[:sessions_deleted]}"
puts "  Messages added: #{final_stats[:messages_added]}"
puts "  Context retrievals: #{final_stats[:context_retrievals]}"

# Cleanup
manager.shutdown
puts "\n--- Manager Shutdown Complete ---\n"
