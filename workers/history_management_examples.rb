# History Management Example Workers
# These examples demonstrate the new intelligent history management features
# introduced in the history-optimization feature.
#
# Key Features Demonstrated:
# 1. Explicit session management with unique session IDs
# 2. Different context strategies (sliding window, relevance-based, summary-based, hybrid)
# 3. Session operations (clear, export, search, stats, delete)
# 4. Backward compatibility with existing API
#
# Requirements Validated: 5.5

# ============================================================================
# Example 1: Explicit Session Management
# ============================================================================
# Demonstrates: Requirement 1 (Session Isolation), Requirement 5.2 (Default Sessions)

# Simple chat worker with automatic session management
# When with_history: true is used without a session_id, a default session is created
SmartPrompt.define_worker :basic_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful AI assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg
end

# Chat worker with explicit session management
# Use session_id to maintain separate conversations
# Each session maintains isolated history (Requirement 1.1-1.4)
SmartPrompt.define_worker :explicit_session_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Session ID can be user ID, conversation ID, or any unique identifier
  session_id = params[:session_id] || "default_session"
  
  sys_msg("You are a helpful AI assistant.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  send_msg
end

# Multi-user chat with isolated sessions per user
# Demonstrates: Session isolation for concurrent users
SmartPrompt.define_worker :multi_user_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Use user ID as session ID for isolation
  user_id = params[:user_id] || raise("user_id is required")
  session_id = "user_#{user_id}"
  
  # Configure per-user session with limits (Requirement 2.1-2.2)
  session_config = {
    max_messages: 50,
    max_tokens: 3000,
    context_strategy: :sliding_window,
    preserve_system_messages: true
  }
  
  user_name = params[:user_name] || "User"
  sys_msg("You are a personal AI assistant for #{user_name}.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  # Apply session configuration
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# ============================================================================
# Example 2: Different Context Strategies
# ============================================================================
# Demonstrates: Requirement 6.1 (Context Strategy Configuration), 
#               Requirement 8.2 (Multiple Strategy Support)

# 2.1 Sliding Window Strategy
# Keeps most recent N messages - Best for: Real-time chat, customer support
SmartPrompt.define_worker :sliding_window_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "sliding_window_session"
  
  # Configure session with sliding window strategy (Requirement 8.2)
  session_config = {
    max_messages: 20,
    max_tokens: 2000,
    context_strategy: :sliding_window,
    preserve_system_messages: true  # Requirement 2.5
  }
  
  sys_msg("You are a helpful customer support assistant.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  # Apply session configuration
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# 2.2 Relevance-Based Strategy
# Selects semantically relevant messages - Best for: Q&A systems, knowledge bases
SmartPrompt.define_worker :relevance_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "relevance_session"
  
  # Configure session with relevance-based strategy (Requirement 8.1, 8.3)
  session_config = {
    max_messages: 100,
    max_tokens: 4000,
    context_strategy: :relevance_based,
    preserve_system_messages: true
  }
  
  sys_msg("You are a knowledgeable AI assistant that provides accurate answers.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# 2.3 Summary-Based Strategy
# Automatically compresses old messages - Best for: Long conversations, extended dialogues
SmartPrompt.define_worker :summary_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "summary_session"
  
  # Configure session with summary-based strategy (Requirement 9.1-9.3)
  session_config = {
    max_messages: 200,
    max_tokens: 8000,
    context_strategy: :summary_based,
    preserve_system_messages: true
  }
  
  sys_msg("You are a thoughtful AI assistant for extended conversations.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# 2.4 Hybrid Strategy
# Adaptively combines multiple strategies - Best for: General-purpose applications
SmartPrompt.define_worker :hybrid_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "hybrid_session"
  
  # Configure session with hybrid strategy (Requirement 6.1)
  session_config = {
    max_messages: 150,
    max_tokens: 6000,
    context_strategy: :hybrid,
    preserve_system_messages: true
  }
  
  sys_msg("You are an intelligent AI assistant that adapts to conversation context.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# ============================================================================
# Example 3: Session Operations (clear, export, search, stats, delete)
# ============================================================================
# Demonstrates: Requirement 4 (Session Management Operations)

# Worker demonstrating all session management operations
SmartPrompt.define_worker :session_operations do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "default_session"
  operation = params[:operation] # :clear, :export, :search, :stats, :delete
  
  case operation
  when :clear
    # Clear session history (keeps system messages by default) - Requirement 4.1
    @engine.history_manager.clear_session(session_id, keep_system_messages: true)
    "Session cleared successfully"
    
  when :export
    # Export session data in structured format - Requirement 4.2
    @engine.history_manager.export_session(session_id, format: :json)
    
  when :search
    # Search for messages containing specific text - Requirement 4.3
    query = params[:query]
    results = @engine.history_manager.search_messages(session_id, query)
    "Found #{results.count} messages matching '#{query}'"
    
  when :stats
    # Get session statistics (message count, token usage) - Requirement 4.4
    @engine.history_manager.get_stats(session_id)
    
  when :delete
    # Delete session completely (memory and disk) - Requirement 4.5
    @engine.history_manager.delete_session(session_id)
    "Session deleted successfully"
    
  else
    "Unknown operation: #{operation}"
  end
end

# Example: Get system-wide statistics
SmartPrompt.define_worker :system_stats do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Get system-wide statistics - Requirement 11.3
  stats = @engine.history_manager.get_stats
  
  {
    active_sessions: stats[:active_sessions],
    total_messages: stats[:total_messages],
    total_tokens: stats[:total_tokens],
    cache_hit_rate: stats[:cache_hit_rate],
    messages_added: stats[:messages_added],
    context_retrievals: stats[:context_retrievals]
  }
end

# Example: Export metrics in Prometheus format
SmartPrompt.define_worker :export_metrics do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Export metrics in Prometheus format - Requirement 11.5
  @engine.history_manager.export_metrics(format: :prometheus)
end

# ============================================================================
# Example 4: Backward Compatibility
# ============================================================================
# Demonstrates: Requirement 5 (Backward Compatibility)

# Old-style worker definition (still works!) - Requirement 5.1, 5.4
SmartPrompt.define_worker :legacy_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful AI assistant.", params)
  
  # Old-style history usage - still works!
  # Automatically creates a default session - Requirement 5.2
  prompt(params[:message], with_history: true)
  
  send_msg(with_history: true)
end

# Worker showing compatibility mode - Requirement 5.3
SmartPrompt.define_worker :compatibility_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful AI assistant.", params)
  
  # Works with both old and new API
  if params[:session_id]
    # New API: explicit session management
    prompt(params[:message], with_history: true, session_id: params[:session_id])
  else
    # Old API: automatic default session
    prompt(params[:message], with_history: true)
  end
  
  send_msg
end

# ============================================================================
# Example 5: Advanced Use Cases
# ============================================================================

# Streaming with history management
SmartPrompt.define_worker :streaming_history_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "streaming_session"
  
  sys_msg("You are a helpful AI assistant.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  # Use send_msg_by_stream for streaming responses
  # History is still maintained automatically
  send_msg_by_stream(params)
end

# Custom configuration for specific use cases
SmartPrompt.define_worker :custom_config_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "custom_session"
  
  # Fine-tuned configuration for a code review assistant
  session_config = {
    max_messages: 100,
    max_tokens: 8000,
    context_strategy: :relevance_based,
    preserve_system_messages: true
  }
  
  sys_msg("You are an expert code reviewer. Analyze code and provide constructive feedback.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  @engine.history_manager.get_session(session_id, session_config)
  
  send_msg
end

# Persistence example - sessions are automatically saved to disk (Requirement 3.1-3.3)
SmartPrompt.define_worker :persistent_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "persistent_session"
  
  # Sessions are automatically persisted to disk
  # They will be restored on next access
  sys_msg("You are a helpful AI assistant. Your conversations are saved.", params)
  prompt(params[:message], with_history: true, session_id: session_id)
  
  send_msg
end

# ============================================================================
# Usage Examples
# ============================================================================
# 
# Example 1: Basic usage with automatic session
#   SmartPrompt.run_worker(:basic_chat, { message: "Hello!" })
#
# Example 2: Explicit session management
#   SmartPrompt.run_worker(:explicit_session_chat, { 
#     session_id: "user_123", 
#     message: "Hello!" 
#   })
#
# Example 3: Multi-user chat
#   SmartPrompt.run_worker(:multi_user_chat, { 
#     user_id: "001", 
#     user_name: "Alice",
#     message: "Hi!" 
#   })
#
# Example 4: Using different strategies
#   SmartPrompt.run_worker(:sliding_window_chat, { message: "Hello!" })
#   SmartPrompt.run_worker(:relevance_chat, { message: "Hello!" })
#   SmartPrompt.run_worker(:summary_chat, { message: "Hello!" })
#   SmartPrompt.run_worker(:hybrid_chat, { message: "Hello!" })
#
# Example 5: Session operations
#   # Get statistics
#   SmartPrompt.run_worker(:session_operations, { 
#     session_id: "user_123", 
#     operation: :stats 
#   })
#   
#   # Search messages
#   SmartPrompt.run_worker(:session_operations, { 
#     session_id: "user_123", 
#     operation: :search,
#     query: "Ruby" 
#   })
#   
#   # Export session
#   SmartPrompt.run_worker(:session_operations, { 
#     session_id: "user_123", 
#     operation: :export 
#   })
#   
#   # Clear session
#   SmartPrompt.run_worker(:session_operations, { 
#     session_id: "user_123", 
#     operation: :clear 
#   })
#   
#   # Delete session
#   SmartPrompt.run_worker(:session_operations, { 
#     session_id: "user_123", 
#     operation: :delete 
#   })
#
# Example 6: System-wide statistics
#   SmartPrompt.run_worker(:system_stats, {})
#
# Example 7: Export Prometheus metrics
#   SmartPrompt.run_worker(:export_metrics, {})
#
# Example 8: Backward compatibility (old API)
#   SmartPrompt.run_worker(:legacy_chat, { message: "Hello!" })
#
# ============================================================================
