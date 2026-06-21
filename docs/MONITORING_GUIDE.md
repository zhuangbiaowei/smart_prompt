# History Manager Monitoring Guide

This guide explains the logging and monitoring features available in the SmartPrompt History Manager.

## Overview

The History Manager includes comprehensive logging and monitoring capabilities to help you:
- Track system operations and performance
- Debug context selection decisions
- Monitor resource usage and cache efficiency
- Export metrics for external monitoring systems

## Configuration

Enable monitoring in your configuration:

```ruby
config = {
  monitoring: {
    enabled: true,        # Enable/disable monitoring
    log_level: :info      # Log level: :debug, :info, :warn, :error
  }
}

manager = SmartPrompt::HistoryManager.new(config)
```

## Log Levels

### INFO Level
Logs important operations:
- Session creation and deletion
- Message additions
- Context retrievals
- Session clearing and exports
- Cleanup operations

Example:
```
[HistoryManager] Session user_123 created with config: max_messages=100, max_tokens=4000
[HistoryManager] Message added to session user_123: role=user, tokens=15
[HistoryManager] Session user_123 cleared: 10 -> 1 messages (keep_system=true)
```

### DEBUG Level
Logs detailed information for debugging:
- Cache hits and misses
- Context selection decisions
- Strategy selection in hybrid mode
- Token trimming operations
- Importance scores

Example:
```
[HistoryManager] Session user_123 retrieved from cache
[SlidingWindowStrategy] selected 5/10 messages (window_size=5, system=0, recent=5)
[RelevanceBasedStrategy] calculated scores for 30 messages, top 5 scores: [0.85, 0.82, 0.79, 0.75, 0.72]
[HybridStrategy] Adaptive mode: selected RelevanceBasedStrategy for 30 messages
```

### ERROR Level
Logs errors with context:
- Persistence failures
- Compression errors
- Operation failures

Example:
```
[HistoryManager] Persistence failed for session user_123: Errno::ENOSPC - No space left on device
[HistoryManager] Failed to add message to session user_123: ArgumentError - Invalid message format
```

## Statistics and Metrics

### Session-Specific Statistics

Get statistics for a specific session:

```ruby
stats = manager.get_stats("session_id")

# Returns:
{
  session_id: "session_id",
  message_count: 25,
  total_tokens: 1500,
  created_at: <Time>,
  updated_at: <Time>,
  config: { ... }
}
```

### System-Wide Statistics

Get statistics for all sessions:

```ruby
stats = manager.get_stats

# Returns:
{
  # Session metrics
  active_sessions: 10,
  sessions_created: 50,
  sessions_deleted: 40,
  
  # Message metrics
  total_messages: 250,
  messages_added: 300,
  messages_per_session_avg: 25.0,
  
  # Token metrics
  total_tokens: 15000,
  tokens_per_session_avg: 1500.0,
  tokens_per_message_avg: 60.0,
  
  # Cache metrics
  cache_size: 100,
  cache_hits: 850,
  cache_misses: 150,
  cache_hit_rate: 0.85,
  
  # Operation metrics
  context_retrievals: 200,
  
  # Compression metrics
  compression_operations: 5,
  tokens_saved_by_compression: 5000,
  
  # Error metrics
  persistence_errors: 2
}
```

## Metrics Export

Export metrics in various formats for integration with monitoring systems.

### Prometheus Format

```ruby
metrics = manager.export_metrics(format: :prometheus)

# Returns Prometheus-style metrics:
# HELP smart_prompt_active_sessions Number of active sessions in cache
# TYPE smart_prompt_active_sessions gauge
smart_prompt_active_sessions 10

# HELP smart_prompt_cache_hit_rate Cache hit rate (0.0-1.0)
# TYPE smart_prompt_cache_hit_rate gauge
smart_prompt_cache_hit_rate 0.85
```

### JSON Format

```ruby
metrics = manager.export_metrics(format: :json)

# Returns JSON string with all metrics
```

### Hash Format

```ruby
metrics = manager.export_metrics(format: :hash)

# Returns Ruby hash with all metrics
```

## Context Selection Debugging

When debug logging is enabled, you can see detailed information about context selection:

```ruby
# Enable debug logging
SmartPrompt.logger.level = Logger::DEBUG

# Retrieve context
context = manager.get_context("session_id", max_tokens: 1000)

# Debug output shows:
# - Which strategy was selected (for hybrid mode)
# - How many messages were considered
# - How many messages were selected
# - Token counts before and after trimming
# - Importance scores for relevance-based selection
```

## Performance Monitoring

Track key performance indicators:

```ruby
stats = manager.get_stats

# Cache efficiency
cache_hit_rate = stats[:cache_hit_rate]
puts "Cache hit rate: #{(cache_hit_rate * 100).round(2)}%"

# Average resource usage
avg_messages = stats[:messages_per_session_avg]
avg_tokens = stats[:tokens_per_session_avg]
puts "Avg messages per session: #{avg_messages.round(2)}"
puts "Avg tokens per session: #{avg_tokens.round(2)}"

# Compression effectiveness
if stats[:compression_operations] > 0
  tokens_saved = stats[:tokens_saved_by_compression]
  puts "Tokens saved by compression: #{tokens_saved}"
end
```

## Error Tracking

Monitor errors to identify issues:

```ruby
stats = manager.get_stats

if stats[:persistence_errors] > 0
  puts "Warning: #{stats[:persistence_errors]} persistence errors occurred"
  # Check logs for details
end
```

## Best Practices

1. **Use INFO level in production** - Provides good visibility without excessive logging
2. **Use DEBUG level for troubleshooting** - Helps diagnose context selection issues
3. **Monitor cache hit rate** - Low hit rates may indicate cache size is too small
4. **Track compression metrics** - Verify compression is reducing token usage
5. **Export metrics regularly** - Integrate with monitoring systems like Prometheus
6. **Set up alerts** - Alert on high error rates or low cache hit rates

## Example: Complete Monitoring Setup

```ruby
require 'smart_prompt'
require 'logger'

# Configure logger
SmartPrompt.logger = Logger.new('history_manager.log')
SmartPrompt.logger.level = Logger::INFO

# Configure manager with monitoring
config = {
  cache_size: 100,
  monitoring: {
    enabled: true,
    log_level: :info
  }
}

manager = SmartPrompt::HistoryManager.new(config)

# Use the manager
manager.add_message("user_123", { role: "user", content: "Hello" })

# Periodically export metrics
Thread.new do
  loop do
    sleep 60  # Every minute
    metrics = manager.export_metrics(format: :prometheus)
    File.write('metrics.prom', metrics)
  end
end

# Check statistics
stats = manager.get_stats
puts "Active sessions: #{stats[:active_sessions]}"
puts "Cache hit rate: #{(stats[:cache_hit_rate] * 100).round(2)}%"
```

## See Also

- [History Optimization Design Document](.kiro/specs/history-optimization/design.md)
- [Monitoring Example](examples/monitoring_example.rb)
- [History Manager Tests](test/monitoring_test.rb)
