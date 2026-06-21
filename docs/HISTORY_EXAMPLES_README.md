# History Management Examples

This directory contains comprehensive examples demonstrating the new intelligent history management features in SmartPrompt.

## Overview

The history management system provides:

- **Session Isolation**: Each conversation has its own isolated history
- **Intelligent Context Management**: Multiple strategies for selecting relevant messages
- **Automatic Compression**: Summarize old messages to save tokens
- **Persistence**: Save and restore conversations from disk
- **Monitoring**: Track usage statistics and metrics
- **Backward Compatibility**: Works seamlessly with existing code

## Quick Start

### Running the Examples

```bash
# Run all examples
ruby examples/history_management_examples.rb

# Or run specific sections by modifying the file
```

### Basic Usage

```ruby
require 'smart_prompt'

# Simple chat with automatic session management
engine.call_worker(:basic_chat, {
  message: "Hello! How are you?"
})

# Chat with explicit session ID
engine.call_worker(:explicit_session_chat, {
  session_id: "user_123",
  message: "Hello! How are you?"
})
```

## Examples Included

### 1. Explicit Session Management

Demonstrates how to create and manage isolated conversation sessions.

**Key Features:**
- Unique session IDs for each conversation
- Session isolation (no cross-contamination)
- Multi-user support

**Requirements Validated:** 1.1, 1.2, 1.3, 1.4, 5.2

**Example:**
```ruby
# User 1's conversation
SmartPrompt.run_worker(:explicit_session_chat, {
  session_id: "user_alice",
  message: "My name is Alice."
})

# User 2's conversation (completely isolated)
SmartPrompt.run_worker(:explicit_session_chat, {
  session_id: "user_bob",
  message: "My name is Bob."
})

# Continue User 1's conversation
SmartPrompt.run_worker(:explicit_session_chat, {
  session_id: "user_alice",
  message: "What's my name?" # Will remember "Alice"
})
```

### 2. Different Context Strategies

Demonstrates the four available context strategies for managing conversation history.

#### 2.1 Sliding Window Strategy

Keeps the most recent N messages. Best for real-time chat and customer support.

**Requirements Validated:** 8.2

**Example:**
```ruby
SmartPrompt.run_worker(:sliding_window_chat, {
  session_id: "support_001",
  message: "I need help with my account."
})
```

**Configuration:**
- `max_messages: 20` - Keep last 20 messages
- `max_tokens: 2000` - Maximum 2000 tokens
- `preserve_system_messages: true` - Always keep system messages

#### 2.2 Relevance-Based Strategy

Selects semantically relevant messages based on importance scoring. Best for Q&A systems and knowledge bases.

**Requirements Validated:** 8.1, 8.3

**Example:**
```ruby
SmartPrompt.run_worker(:relevance_chat, {
  session_id: "qa_001",
  message: "Tell me about Ruby programming."
})

# Later in the conversation...
SmartPrompt.run_worker(:relevance_chat, {
  session_id: "qa_001",
  message: "What were the Ruby features we discussed?"
  # Will include relevant earlier messages even if not recent
})
```

**Configuration:**
- `max_messages: 100` - Consider up to 100 messages
- `max_tokens: 4000` - Maximum 4000 tokens
- Importance scoring based on recency and relevance

#### 2.3 Summary-Based Strategy

Automatically compresses old messages into summaries. Best for long conversations and extended dialogues.

**Requirements Validated:** 9.1, 9.2, 9.3

**Example:**
```ruby
SmartPrompt.run_worker(:summary_chat, {
  session_id: "long_conv_001",
  message: "Let's discuss the history of computing."
})

# After many messages, old ones are automatically summarized
```

**Configuration:**
- `max_messages: 200` - Can handle up to 200 messages
- `max_tokens: 8000` - Maximum 8000 tokens
- Automatic summarization when threshold is reached

#### 2.4 Hybrid Strategy

Adaptively combines multiple strategies based on conversation characteristics. Best for general-purpose applications.

**Requirements Validated:** 6.1

**Example:**
```ruby
SmartPrompt.run_worker(:hybrid_chat, {
  session_id: "general_001",
  message: "Let's talk about various topics."
})
```

**Configuration:**
- `max_messages: 150` - Balanced message limit
- `max_tokens: 6000` - Balanced token limit
- Automatically switches between strategies based on conversation state

### 3. Session Operations

Demonstrates all available session management operations.

**Requirements Validated:** 4.1, 4.2, 4.3, 4.4, 4.5

#### Get Statistics

```ruby
stats = SmartPrompt.run_worker(:session_operations, {
  session_id: "user_123",
  operation: :stats
})

# Returns:
# {
#   session_id: "user_123",
#   message_count: 15,
#   total_tokens: 1234,
#   created_at: <timestamp>,
#   updated_at: <timestamp>,
#   config: {...}
# }
```

#### Search Messages

```ruby
results = SmartPrompt.run_worker(:session_operations, {
  session_id: "user_123",
  operation: :search,
  query: "Ruby programming"
})

# Returns: "Found 3 messages matching 'Ruby programming'"
```

#### Export Session

```ruby
data = SmartPrompt.run_worker(:session_operations, {
  session_id: "user_123",
  operation: :export
})

# Returns JSON with all session data
```

#### Clear Session

```ruby
SmartPrompt.run_worker(:session_operations, {
  session_id: "user_123",
  operation: :clear
})

# Removes all messages except system messages
```

#### Delete Session

```ruby
SmartPrompt.run_worker(:session_operations, {
  session_id: "user_123",
  operation: :delete
})

# Completely removes session from memory and disk
```

### 4. Backward Compatibility

Demonstrates that existing code continues to work without modifications.

**Requirements Validated:** 5.1, 5.2, 5.3, 5.4

**Example:**
```ruby
# Old API - still works!
SmartPrompt.run_worker(:legacy_chat, {
  message: "Hello!"
})

# Automatically creates a default session
# Benefits from new features without code changes
```

### 5. Advanced Use Cases

#### Multi-User Chat Application

```ruby
# User 1
SmartPrompt.run_worker(:multi_user_chat, {
  user_id: "001",
  user_name: "Alice",
  message: "Hi! I'm working on a Ruby project."
})

# User 2 (completely isolated)
SmartPrompt.run_worker(:multi_user_chat, {
  user_id: "002",
  user_name: "Bob",
  message: "Hello! I need help with Python."
})
```

#### Streaming with History

```ruby
SmartPrompt.run_worker(:streaming_history_chat, {
  session_id: "stream_001",
  message: "Tell me a long story."
})

# Streams response while maintaining history
```

#### Custom Configuration

```ruby
SmartPrompt.run_worker(:custom_config_chat, {
  session_id: "code_review_001",
  message: "Please review this code: def hello; puts 'world'; end"
})

# Uses fine-tuned configuration for code review
```

#### Persistent Sessions

```ruby
SmartPrompt.run_worker(:persistent_chat, {
  session_id: "persistent_001",
  message: "This conversation will be saved to disk."
})

# Session is automatically saved and can be restored later
```

### 6. Monitoring and Debugging

#### System-Wide Statistics

```ruby
stats = SmartPrompt.run_worker(:system_stats, {})

# Returns:
# {
#   active_sessions: 5,
#   total_messages: 123,
#   total_tokens: 12345,
#   cache_hit_rate: 0.85,
#   messages_added: 150,
#   context_retrievals: 75
# }
```

#### Export Prometheus Metrics

```ruby
metrics = SmartPrompt.run_worker(:export_metrics, {})

# Returns Prometheus-formatted metrics:
# smart_prompt_active_sessions 5
# smart_prompt_total_messages 123
# smart_prompt_cache_hit_rate 0.85
# ...
```

## Configuration Options

### Session Configuration

```ruby
session_config = {
  max_messages: 100,              # Maximum number of messages to keep
  max_tokens: 4000,               # Maximum token count
  context_strategy: :sliding_window,  # Strategy: :sliding_window, :relevance_based, :summary_based, :hybrid
  preserve_system_messages: true  # Always keep system messages
}
```

### Global Configuration

Configure the history manager in your `config/anthropic_config.yml`:

```yaml
history:
  cache_size: 100                 # Maximum sessions in cache
  
  session_defaults:
    max_messages: 100
    max_tokens: 4000
    context_strategy: sliding_window
    preserve_system_messages: true
  
  persistence:
    enabled: true
    backend: filesystem
    storage_path: "./history_data"
    async: true
  
  cleanup:
    auto_cleanup: true
    cleanup_interval: 3600        # 1 hour
    session_ttl: 86400            # 24 hours
  
  monitoring:
    enabled: true
    log_level: info
```

## Best Practices

### 1. Choose the Right Strategy

- **Sliding Window**: Use for real-time chat, customer support, or when you only need recent context
- **Relevance-Based**: Use for Q&A systems, knowledge bases, or when semantic relevance matters
- **Summary-Based**: Use for long conversations, documentation, or when you need to preserve history
- **Hybrid**: Use for general-purpose applications or when conversation patterns vary

### 2. Set Appropriate Limits

```ruby
# For short conversations
max_messages: 20
max_tokens: 2000

# For medium conversations
max_messages: 50
max_tokens: 4000

# For long conversations
max_messages: 100
max_tokens: 8000
```

### 3. Use Meaningful Session IDs

```ruby
# Good: Descriptive and unique
session_id: "user_#{user_id}"
session_id: "conversation_#{conversation_id}"
session_id: "support_ticket_#{ticket_id}"

# Bad: Generic or non-unique
session_id: "session"
session_id: "default"
```

### 4. Clean Up Old Sessions

```ruby
# Manually trigger cleanup
engine.history_manager.cleanup_expired_sessions

# Or enable automatic cleanup
cleanup: {
  auto_cleanup: true,
  cleanup_interval: 3600,  # Check every hour
  session_ttl: 86400       # Delete after 24 hours
}
```

### 5. Monitor Performance

```ruby
# Regularly check statistics
stats = engine.history_manager.get_stats

# Monitor cache hit rate (should be > 0.7)
puts "Cache hit rate: #{stats[:cache_hit_rate]}"

# Monitor token usage
puts "Average tokens per session: #{stats[:tokens_per_session_avg]}"
```

## Troubleshooting

### Session Not Found

If a session is not found, it may have been evicted from cache or deleted:

```ruby
# Check if session exists
if engine.history_manager.session_exists?(session_id)
  # Session exists
else
  # Session was deleted or never created
end
```

### High Memory Usage

If memory usage is high:

1. Reduce `cache_size` in configuration
2. Enable automatic cleanup
3. Reduce `max_messages` and `max_tokens` per session
4. Use summary-based strategy for long conversations

### Slow Performance

If performance is slow:

1. Check cache hit rate (should be > 0.7)
2. Reduce `max_messages` to speed up context retrieval
3. Use sliding window strategy for faster selection
4. Enable async persistence

## Migration Guide

### From Old History API

The new system is backward compatible. No changes required!

```ruby
# Old code - still works
SmartPrompt.define_worker :old_worker do
  prompt(params[:message], with_history: true)
  send_msg(with_history: true)
end

# New code - with explicit session management
SmartPrompt.define_worker :new_worker do
  session_id = params[:session_id]
  prompt(params[:message], with_history: true, session_id: session_id)
  send_msg
end
```

### Gradual Migration

1. Start using explicit session IDs for new features
2. Keep existing workers unchanged
3. Gradually migrate to new API as needed
4. Both APIs work simultaneously

## Requirements Coverage

This example set validates the following requirements:

- **Requirement 1**: Session Isolation (1.1, 1.2, 1.3, 1.4)
- **Requirement 2**: Message and Token Limits (2.1, 2.2, 2.3, 2.4, 2.5)
- **Requirement 3**: Persistence (3.1, 3.2, 3.3)
- **Requirement 4**: Session Operations (4.1, 4.2, 4.3, 4.4, 4.5)
- **Requirement 5**: Backward Compatibility (5.1, 5.2, 5.3, 5.4, 5.5)
- **Requirement 6**: Configuration (6.1)
- **Requirement 8**: Intelligent Context Management (8.1, 8.2, 8.3)
- **Requirement 9**: Automatic Compression (9.1, 9.2, 9.3)
- **Requirement 11**: Monitoring (11.3, 11.5)

## Additional Resources

- [Design Document](.kiro/specs/history-optimization/design.md)
- [Requirements Document](.kiro/specs/history-optimization/requirements.md)
- [Implementation Tasks](.kiro/specs/history-optimization/tasks.md)
- [Main README](../README.md)

## Support

For questions or issues:
1. Check the design document for detailed architecture
2. Review the requirements document for expected behavior
3. Examine the worker examples in `workers/history_management_examples.rb`
4. Run the comprehensive examples in this directory
