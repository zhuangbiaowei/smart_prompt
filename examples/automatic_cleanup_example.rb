#!/usr/bin/env ruby
# Example demonstrating automatic cleanup functionality in HistoryManager

require_relative '../lib/smart_prompt'

puts "=== Automatic Cleanup Example ==="
puts

# Example 1: Manual cleanup with TTL
puts "1. Manual cleanup with TTL"
puts "-" * 50

manager = SmartPrompt::HistoryManager.new(
  cleanup: {
    auto_cleanup: false,  # Manual cleanup
    session_ttl: 5,       # 5 seconds TTL
    cleanup_interval: 10
  }
)

# Create some sessions
manager.add_message("session1", { role: "user", content: "Message in session 1" })
manager.add_message("session2", { role: "user", content: "Message in session 2" })

puts "Created 2 sessions"
puts "Active sessions: #{manager.session_ids.join(', ')}"
puts

# Wait for sessions to expire
puts "Waiting 6 seconds for sessions to expire..."
sleep(6)

# Manually trigger cleanup
expired = manager.cleanup_expired_sessions
puts "Cleaned up #{expired.length} expired sessions: #{expired.join(', ')}"
puts "Active sessions: #{manager.session_ids.join(', ')}"
puts

manager.shutdown

# Example 2: Automatic cleanup with background thread
puts "\n2. Automatic cleanup with background thread"
puts "-" * 50

manager2 = SmartPrompt::HistoryManager.new(
  cleanup: {
    auto_cleanup: true,   # Automatic cleanup enabled
    session_ttl: 3,       # 3 seconds TTL
    cleanup_interval: 2   # Check every 2 seconds
  }
)

# Create a session
manager2.add_message("auto_session", { role: "user", content: "This will be auto-cleaned" })
puts "Created session: auto_session"
puts "Active sessions: #{manager2.session_ids.join(', ')}"
puts

# Wait for automatic cleanup to occur
puts "Waiting 5 seconds for automatic cleanup..."
sleep(5)

puts "Active sessions after automatic cleanup: #{manager2.session_ids.join(', ')}"
puts

manager2.shutdown

# Example 3: Custom cleanup callback
puts "\n3. Custom cleanup callback"
puts "-" * 50

# Custom callback that cleans up sessions with more than 3 messages
custom_callback = lambda do |session, age|
  # Cleanup if session has more than 3 messages OR is older than 10 seconds
  session.message_count > 3 || age > 10
end

manager3 = SmartPrompt::HistoryManager.new(
  cleanup: {
    auto_cleanup: false,
    session_ttl: 100,  # Long TTL, callback will decide
    cleanup_callback: custom_callback
  }
)

# Create sessions with different message counts
manager3.add_message("small_session", { role: "user", content: "Message 1" })
manager3.add_message("small_session", { role: "user", content: "Message 2" })

manager3.add_message("large_session", { role: "user", content: "Message 1" })
manager3.add_message("large_session", { role: "user", content: "Message 2" })
manager3.add_message("large_session", { role: "user", content: "Message 3" })
manager3.add_message("large_session", { role: "user", content: "Message 4" })
manager3.add_message("large_session", { role: "user", content: "Message 5" })

puts "Created 2 sessions:"
puts "  - small_session: 2 messages"
puts "  - large_session: 5 messages"
puts

# Trigger cleanup with custom callback
expired = manager3.cleanup_expired_sessions
puts "Custom callback cleaned up: #{expired.join(', ')}"
puts "Remaining sessions: #{manager3.session_ids.join(', ')}"
puts

manager3.shutdown

puts "\n=== Example Complete ==="
