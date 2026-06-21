# History Management Usage Guide

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Configuration](#configuration)
4. [Basic Usage](#basic-usage)
5. [Context Strategies](#context-strategies)
6. [Session Management](#session-management)
7. [Advanced Features](#advanced-features)
8. [Migration Guide](#migration-guide)
9. [Best Practices](#best-practices)
10. [Troubleshooting](#troubleshooting)

## Overview

SmartPrompt's History Management system provides intelligent conversation history management with:

- **Session Isolation**: Each conversation has its own independent history
- **Automatic Compression**: Reduce token usage while preserving context
- **Multiple Strategies**: Choose how messages are selected for context
- **Persistence**: Save and restore conversations across restarts
- **Performance**: LRU caching and async I/O for optimal performance
- **Monitoring**: Built-in metrics and logging for debugging

## Quick Start

### 1. Enable History Management

Add to your `config/anthropic_config.yml`:

```yaml
history:
  cache_size: 100
  session_defaults:
    max_messages: 100
    max_tokens: 4000
    context_strategy: sliding_window
    preserve_system_messages: true
  persistence:
    enabled: true
    storage_path: "./history_data"
    async: true
```

### 2. Use in Your Workers

```ruby
SmartPrompt.define_worker :chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg
end
```

### 3. Call the Worker

```ruby
engine = SmartPrompt::Engine.new('config/anthropic_config.yml')

# First message
response1 = engine.call_worker(:chat, {
  message: "What is Ruby?"
})

# Second message (with context from first)
response2 = engine.call_worker(:chat, {
  message: "Can you show me an example?"
})
```

## Configuration

### Complete Configuration Reference

```yaml
history:
  # Cache Configuration
  cache_size: 100                    # Max sessions in memory (LRU eviction)

  # Session Defaults
  session_defaults:
    max_messages: 100                # Max messages per session
    max_tokens: 4000                 # Max tokens per session
    context_strategy: sliding_window # Default strategy
    preserve_system_messages: true   # Keep system messages

  # Strategy Configurations
  strategies:
    sliding_window:
      window_size: 10                # Recent messages to keep
      preserve_system: true
    
    relevance_based:
      top_k: 10                      # Most relevant messages
      recency_weight: 0.3            # Recency importance (0-1)
      relevance_weight: 0.7          # Relevance importance (0-1)
      embedding_service: null        # Optional embedding service
    
    summary_based:
      summary_threshold: 20          # Trigger summarization
      keep_recent: 5                 # Recent messages to keep
      compression_ratio: 0.5         # Target compression
    
    hybrid:
      mode: adaptive                 # 'adaptive' or 'combined'
      sliding_window: {}
      relevance_based: {}
      summary_based: {}

  # Compression
  compression:
    enabled: true
    auto_compress_threshold: 50
    compression_ratio: 0.5
    llm_adapter: null

  # Persistence
  persistence:
    enabled: true
    backend: filesystem
    storage_path: "./history_data"
    async: true

  # Cleanup
  cleanup:
    auto_cleanup: false
    cleanup_interval: 3600           # 1 hour
    session_ttl: 86400               # 24 hours
    cleanup_callback: null

  # Monitoring
  monitoring:
    enabled: true
    log_level: info                  # debug, info, warn, error
    metrics_format: prometheus
```

### Configuration Presets

#### High-Volume Chat Application

```yaml
history:
  cache_size: 1000
  session_defaults:
    max_messages: 50
    max_tokens: 2000
    context_strategy: sliding_window
  cleanup:
    auto_cleanup: true
    session_ttl: 3600  # 1 hour
```

#### Long-Running Conversations

```yaml
history:
  session_defaults:
    max_messages: 500
    max_tokens: 16000
    context_strategy: summary_based
  compression:
    enabled: true
    auto_compress_threshold: 100
```

#### Semantic Search Application

```yaml
history:
  session_defaults:
    context_strategy: relevance_based
  strategies:
    relevance_based:
      top_k: 20
      recency_weight: 0.2
      relevance_weight: 0.8
```

## Basic Usage

### Simple Chat with History

```ruby
SmartPrompt.define_worker :simple_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg
end

# Usage
engine = SmartPrompt::Engine.new('config.yml')
response = engine.call_worker(:simple_chat, {
  message: "Hello!"
})
```

### Chat with Explicit Session ID

```ruby
SmartPrompt.define_worker :session_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "default"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg
end

# Usage - separate conversations
response1 = engine.call_worker(:session_chat, {
  session_id: "user_123",
  message: "What's the weather?"
})

response2 = engine.call_worker(:session_chat, {
  session_id: "user_456",
  message: "Tell me a joke"
})
```

### Streaming with History

```ruby
SmartPrompt.define_worker :streaming_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg_by_stream(params)
end

# Usage
engine.call_worker_by_stream(:streaming_chat, {
  message: "Tell me a story"
}) do |chunk, bytesize|
  print chunk.dig("choices", 0, "delta", "content")
end
```

## Context Strategies

### 1. Sliding Window Strategy

Keeps the most recent N messages. Best for real-time chat and short conversations.

```ruby
SmartPrompt.define_worker :sliding_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_config = {
    max_messages: 20,
    max_tokens: 2000,
    context_strategy: :sliding_window
  }
  
  sys_msg("You are a customer support assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_config: session_config)
  send_msg
end
```

**When to use:**
- Real-time chat applications
- Customer support conversations
- Short, focused interactions
- When recent context is most important

### 2. Relevance-Based Strategy

Selects messages based on semantic similarity to current message. Best for Q&A and knowledge bases.

```ruby
SmartPrompt.define_worker :relevance_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_config = {
    max_messages: 100,
    max_tokens: 4000,
    context_strategy: :relevance_based
  }
  
  sys_msg("You are a knowledgeable assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_config: session_config)
  send_msg
end
```

**When to use:**
- Q&A systems
- Knowledge base assistants
- Context-aware applications
- When semantic relevance matters more than recency

### 3. Summary-Based Strategy

Automatically compresses old messages into summaries. Best for long conversations.

```ruby
SmartPrompt.define_worker :summary_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_config = {
    max_messages: 200,
    max_tokens: 8000,
    context_strategy: :summary_based
  }
  
  sys_msg("You are a thoughtful assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_config: session_config)
  send_msg
end
```

**When to use:**
- Extended conversations
- Documentation generation
- Long-running dialogues
- When token efficiency is critical

### 4. Hybrid Strategy

Adaptively combines multiple strategies. Best for general-purpose applications.

```ruby
SmartPrompt.define_worker :hybrid_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_config = {
    max_messages: 150,
    max_tokens: 6000,
    context_strategy: :hybrid
  }
  
  sys_msg("You are an intelligent assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_config: session_config)
  send_msg
end
```

**When to use:**
- General-purpose applications
- Varied conversation types
- When you want automatic optimization
- Production applications with diverse use cases

## Session Management

### Clear Session History

```ruby
# Clear all messages except system messages
engine.history_manager.clear_session("user_123", keep_system_messages: true)

# Clear all messages including system messages
engine.history_manager.clear_session("user_123", keep_system_messages: false)
```

### Export Session Data

```ruby
# Export as JSON string
json_data = engine.history_manager.export_session("user_123", format: :json)

# Export as Hash
hash_data = engine.history_manager.export_session("user_123", format: :hash)

# Save to file
File.write("session_backup.json", json_data)
```

### Search Messages

```ruby
# Search for messages containing specific text
results = engine.history_manager.search_messages("user_123", "Ruby programming")

results.each do |message|
  puts "#{message.role}: #{message.content}"
end
```

### Get Session Statistics

```ruby
# Session-specific stats
stats = engine.history_manager.get_stats("user_123")
puts "Messages: #{stats[:message_count]}"
puts "Tokens: #{stats[:total_tokens]}"

# System-wide stats
system_stats = engine.history_manager.get_stats
puts "Active sessions: #{system_stats[:active_sessions]}"
puts "Cache hit rate: #{system_stats[:cache_hit_rate]}"
```

### Delete Session

```ruby
# Completely remove session from memory and disk
engine.history_manager.delete_session("user_123")
```

### Check Session Existence

```ruby
if engine.history_manager.session_exists?("user_123")
  puts "Session exists"
end
```

### List All Sessions

```ruby
session_ids = engine.history_manager.session_ids
puts "Active sessions: #{session_ids.join(', ')}"
```

## Advanced Features

### Custom Session Configuration

```ruby
SmartPrompt.define_worker :custom_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Fine-tuned configuration
  session_config = {
    max_messages: 100,
    max_tokens: 8000,
    context_strategy: :relevance_based,
    preserve_system_messages: true,
    strategy_config: {
      top_k: 15,
      recency_weight: 0.4,
      relevance_weight: 0.6
    }
  }
  
  sys_msg("You are a code reviewer.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_config: session_config)
  send_msg
end
```

### Multi-User Applications

```ruby
SmartPrompt.define_worker :multi_user_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  # Isolate sessions by user ID
  user_id = params[:user_id] || raise("user_id required")
  session_id = "user_#{user_id}"
  
  sys_msg("You are #{params[:user_name]}'s assistant.", params)
  prompt(params[:message], with_history: true)
  params.merge(session_id: session_id)
  send_msg
end

# Usage
response = engine.call_worker(:multi_user_chat, {
  user_id: "123",
  user_name: "Alice",
  message: "Hello!"
})
```

### Monitoring and Metrics

```ruby
# Get Prometheus-formatted metrics
metrics = engine.history_manager.export_metrics(format: :prometheus)
puts metrics

# Get JSON metrics
json_metrics = engine.history_manager.export_metrics(format: :json)

# Get raw hash
hash_metrics = engine.history_manager.export_metrics(format: :hash)
```

### Manual Cleanup

```ruby
# Manually trigger cleanup of expired sessions
expired = engine.history_manager.cleanup_expired_sessions
puts "Cleaned up #{expired.count} sessions"
```

### Custom Cleanup Logic

```yaml
# In config file
history:
  cleanup:
    auto_cleanup: true
    cleanup_interval: 3600
    cleanup_callback: !ruby/object:Proc |
      lambda do |session, age|
        # Custom logic: cleanup if inactive for 2 hours
        age > 7200
      end
```

## Migration Guide

### From Old History Implementation

The new history management system is **backward compatible**. Existing code continues to work without changes.

#### Old Code (Still Works)

```ruby
SmartPrompt.define_worker :old_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg(with_history: true)
end
```

#### New Code (Recommended)

```ruby
SmartPrompt.define_worker :new_chat do
  use "deepseek_anthropic"
  model "deepseek-chat"
  
  session_id = params[:session_id] || "default"
  
  sys_msg("You are a helpful assistant.", params)
  prompt(params[:message], with_history: true)
  send_msg
end
```

### Migration Steps

1. **Enable History Management** in your config file:

```yaml
history:
  cache_size: 100
  session_defaults:
    max_messages: 100
    max_tokens: 4000
    context_strategy: sliding_window
  persistence:
    enabled: true
    storage_path: "./history_data"
```

2. **Update Workers Gradually**:
   - Old workers continue to work
   - Add `session_id` parameter for session isolation
   - Configure strategies as needed

3. **Test in Development**:
   - Enable debug logging: `log_level: debug`
   - Monitor statistics: `engine.history_manager.get_stats`
   - Verify session isolation

4. **Deploy to Production**:
   - Start with conservative limits
   - Monitor performance metrics
   - Adjust configuration based on usage

### Breaking Changes

**None!** The new system is fully backward compatible.

### Deprecation Warnings

If you see deprecation warnings, update your code:

```ruby
# Deprecated (but still works)
@engine.history_messages

# Recommended
@engine.history_manager.get_context(session_id)
```

## Best Practices

### 1. Choose the Right Strategy

- **Sliding Window**: Real-time chat, customer support
- **Relevance-Based**: Q&A, knowledge bases
- **Summary-Based**: Long conversations, documentation
- **Hybrid**: General-purpose, production apps

### 2. Set Appropriate Limits

```ruby
# For short conversations
max_messages: 20
max_tokens: 2000

# For long conversations
max_messages: 200
max_tokens: 8000

# For extended dialogues
max_messages: 500
max_tokens: 16000
```

### 3. Use Session IDs Effectively

```ruby
# User-based sessions
session_id = "user_#{user_id}"

# Conversation-based sessions
session_id = "conv_#{conversation_id}"

# Thread-based sessions
session_id = "thread_#{thread_id}"

# Temporary sessions
session_id = "temp_#{SecureRandom.uuid}"
```

### 4. Enable Persistence for Production

```yaml
persistence:
  enabled: true
  storage_path: "./history_data"
  async: true  # Better performance
```

### 5. Configure Cleanup

```yaml
cleanup:
  auto_cleanup: true
  cleanup_interval: 3600  # 1 hour
  session_ttl: 86400      # 24 hours
```

### 6. Monitor Performance

```ruby
# Regular monitoring
stats = engine.history_manager.get_stats
puts "Cache hit rate: #{stats[:cache_hit_rate]}"
puts "Active sessions: #{stats[:active_sessions]}"

# Export metrics for monitoring tools
metrics = engine.history_manager.export_metrics(format: :prometheus)
```

### 7. Handle Errors Gracefully

```ruby
begin
  response = engine.call_worker(:chat, params)
rescue SmartPrompt::HistoryManagerError => e
  logger.error "History error: #{e.message}"
  # Fallback to stateless conversation
end
```

### 8. Test Session Isolation

```ruby
# Ensure sessions don't leak
response1 = engine.call_worker(:chat, {
  session_id: "session_1",
  message: "Remember: my name is Alice"
})

response2 = engine.call_worker(:chat, {
  session_id: "session_2",
  message: "What's my name?"
})

# response2 should not know the name
```

## Troubleshooting

### Issue: Sessions Not Persisting

**Solution**: Check persistence configuration

```yaml
persistence:
  enabled: true
  storage_path: "./history_data"  # Ensure directory exists and is writable
```

### Issue: High Memory Usage

**Solution**: Reduce cache size and enable cleanup

```yaml
cache_size: 50  # Reduce from 100
cleanup:
  auto_cleanup: true
  session_ttl: 3600  # 1 hour instead of 24
```

### Issue: Context Too Large

**Solution**: Reduce token limits or use compression

```yaml
session_defaults:
  max_tokens: 2000  # Reduce from 4000
compression:
  enabled: true
  auto_compress_threshold: 30
```

### Issue: Slow Performance

**Solution**: Enable async persistence and increase cache

```yaml
cache_size: 200  # Increase cache
persistence:
  async: true  # Enable async writes
```

### Issue: Sessions Not Isolated

**Solution**: Ensure unique session IDs

```ruby
# Wrong - same session for all users
session_id = "default"

# Correct - unique per user
session_id = "user_#{params[:user_id]}"
```

### Issue: Debug Logging

**Solution**: Enable debug mode

```yaml
monitoring:
  enabled: true
  log_level: debug  # See detailed logs
```

### Issue: Metrics Not Available

**Solution**: Ensure monitoring is enabled

```yaml
monitoring:
  enabled: true
  metrics_format: prometheus
```

## Support

For more help:

- 📖 [Main Documentation](README.md)
- 🐛 [Issue Tracker](https://github.com/zhuangbiaowei/smart_prompt/issues)
- 💬 [Discussions](https://github.com/zhuangbiaowei/smart_prompt/discussions)
- 📧 Email: zbw@kaiyuanshe.org

---

**SmartPrompt History Management** - Intelligent conversation history for production applications.
