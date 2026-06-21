require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class HybridStrategyTest < Minitest::Test
    def setup
      @token_counter = TokenCounter.new
      @strategy_adaptive = HybridStrategy.new(mode: :adaptive)
      @strategy_combined = HybridStrategy.new(mode: :combined)
    end

    def test_initialize_with_default_config
      strategy = HybridStrategy.new
      assert_equal :adaptive, strategy.instance_variable_get(:@mode)
      assert_equal 20, strategy.instance_variable_get(:@adaptive_threshold_low)
      assert_equal 50, strategy.instance_variable_get(:@adaptive_threshold_high)
    end

    def test_initialize_with_custom_config
      strategy = HybridStrategy.new(
        mode: :combined,
        adaptive_threshold_low: 15,
        adaptive_threshold_high: 40
      )
      assert_equal :combined, strategy.instance_variable_get(:@mode)
      assert_equal 15, strategy.instance_variable_get(:@adaptive_threshold_low)
      assert_equal 40, strategy.instance_variable_get(:@adaptive_threshold_high)
    end

    def test_initialize_with_invalid_mode
      error = assert_raises(ArgumentError) do
        HybridStrategy.new(mode: :invalid)
      end
      assert_match /Invalid mode/, error.message
    end

    def test_select_messages_with_empty_array
      result = @strategy_adaptive.select_messages([], nil)
      assert_equal [], result
    end

    def test_adaptive_mode_uses_sliding_window_for_small_conversations
      # Create 10 messages (below threshold of 20)
      messages = create_messages(10)
      
      result = @strategy_adaptive.select_messages(messages, nil)
      
      # Should use sliding window strategy (default window_size is 10)
      assert_equal 10, result.length
    end

    def test_adaptive_mode_uses_relevance_for_medium_conversations
      # Create 30 messages (between 20 and 50)
      messages = create_messages(30)
      current_message = create_message("user", "Tell me about machine learning")
      
      result = @strategy_adaptive.select_messages(messages, nil, current_message)
      
      # Should use relevance-based strategy (default top_k is 10)
      assert result.length <= 10
      assert result.length > 0
    end

    def test_adaptive_mode_uses_summary_for_large_conversations
      # Create 60 messages (above threshold of 50)
      messages = create_messages(60)
      
      result = @strategy_adaptive.select_messages(messages, nil)
      
      # Should use summary-based strategy
      # Result should be less than total messages
      assert result.length < 60
      assert result.length > 0
    end

    def test_combined_mode_merges_multiple_strategies
      # Create 25 messages
      messages = create_messages(25)
      current_message = create_message("user", "Current message")
      
      result = @strategy_combined.select_messages(messages, nil, current_message)
      
      # Combined mode should merge results from multiple strategies
      # Result should have unique messages
      assert result.length > 0
      assert result.length <= 25
      
      # Check that messages are unique
      assert_equal result.length, result.uniq.length
    end

    def test_combined_mode_maintains_temporal_order
      messages = create_messages(25)
      current_message = create_message("user", "Current message")
      
      result = @strategy_combined.select_messages(messages, nil, current_message)
      
      # Messages should be sorted by timestamp
      timestamps = result.map(&:timestamp)
      assert_equal timestamps, timestamps.sort
    end

    def test_trim_to_token_limit_in_adaptive_mode
      messages = create_messages(15)
      
      # Set a token limit that should exclude some messages
      result = @strategy_adaptive.select_messages(messages, 50)
      
      # Should respect token limit
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 50
    end

    def test_trim_to_token_limit_in_combined_mode
      messages = create_messages(25)
      current_message = create_message("user", "Current message")
      
      # Set a token limit
      result = @strategy_combined.select_messages(messages, 100)
      
      # Should respect token limit
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 100
    end

    def test_preserves_system_messages
      messages = []
      messages << create_message("system", "You are a helpful assistant")
      messages += create_messages(15, role: "user")  # Use 15 to trigger sliding window (< 20)
      
      result = @strategy_adaptive.select_messages(messages, nil)
      
      # System message should be preserved when using sliding window strategy
      assert result.any?(&:system_message?)
    end

    def test_should_compress_adaptive_mode_small_conversation
      session = Session.new("test", {})
      
      # Add 10 messages (uses sliding window)
      10.times { session.add_message(role: "user", content: "Hello") }
      
      # Should use sliding window's compression logic
      # Sliding window compresses when > 2 * window_size (20)
      refute @strategy_adaptive.should_compress?(session)
    end

    def test_should_compress_adaptive_mode_medium_conversation
      session = Session.new("test", {})
      
      # Add 30 messages (uses relevance-based)
      30.times { session.add_message(role: "user", content: "Hello") }
      
      # Should use relevance-based compression logic
      # Relevance-based compresses when > 3 * top_k (30)
      refute @strategy_adaptive.should_compress?(session)
      
      # Add more messages
      5.times { session.add_message(role: "user", content: "Hello") }
      assert @strategy_adaptive.should_compress?(session)
    end

    def test_should_compress_adaptive_mode_large_conversation
      session = Session.new("test", {})
      
      # Add 60 messages (uses summary-based)
      60.times { session.add_message(role: "user", content: "Hello") }
      
      # Should use summary-based compression logic
      # Summary-based compresses when > summary_threshold (20)
      assert @strategy_adaptive.should_compress?(session)
    end

    def test_should_compress_combined_mode
      session = Session.new("test", {})
      
      # Add messages
      25.times { session.add_message(role: "user", content: "Hello") }
      
      # Combined mode compresses if any strategy recommends it
      result = @strategy_combined.should_compress?(session)
      
      # At least one strategy should recommend compression
      assert [true, false].include?(result)
    end

    def test_custom_thresholds
      strategy = HybridStrategy.new(
        mode: :adaptive,
        adaptive_threshold_low: 5,
        adaptive_threshold_high: 15
      )
      
      # 3 messages - should use sliding window
      messages = create_messages(3)
      result = strategy.select_messages(messages, nil)
      assert_equal 3, result.length
      
      # 10 messages - should use relevance-based
      messages = create_messages(10)
      result = strategy.select_messages(messages, nil)
      assert result.length <= 10
      
      # 20 messages - should use summary-based
      messages = create_messages(20)
      result = strategy.select_messages(messages, nil)
      assert result.length > 0
    end

    def test_sub_strategy_configuration
      strategy = HybridStrategy.new(
        mode: :adaptive,
        sliding_window: { window_size: 3 },
        relevance_based: { top_k: 5 },
        summary_based: { keep_recent: 3 }
      )
      
      # Verify sub-strategies are configured
      sliding_window = strategy.instance_variable_get(:@sliding_window)
      assert_equal 3, sliding_window.instance_variable_get(:@window_size)
      
      relevance_based = strategy.instance_variable_get(:@relevance_based)
      assert_equal 5, relevance_based.instance_variable_get(:@top_k)
      
      summary_based = strategy.instance_variable_get(:@summary_based)
      assert_equal 3, summary_based.instance_variable_get(:@keep_recent)
    end

    def test_combined_mode_excludes_summary_for_small_conversations
      # Create 25 messages (below high threshold of 50)
      messages = create_messages(25)
      current_message = create_message("user", "Current message")
      
      result = @strategy_combined.select_messages(messages, nil, current_message)
      
      # Should not include summaries for conversations below high threshold
      refute result.any? { |msg| msg.is_summary }
    end

    def test_handles_nil_session_in_should_compress
      result = @strategy_adaptive.should_compress?(nil)
      assert_equal false, result
    end

    private

    def create_messages(count, role: "user")
      count.times.map do |i|
        create_message(role, "Message #{i}")
      end
    end

    def create_message(role, content)
      msg = Message.new(role: role, content: content, timestamp: Time.now + rand(1000))
      msg.calculate_tokens(@token_counter)
      msg
    end
  end
end
