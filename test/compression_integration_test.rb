require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  # Integration test for CompressionEngine and SummaryBasedStrategy
  class CompressionIntegrationTest < Minitest::Test
    def setup
      @token_counter = TokenCounter.new
      @mock_adapter = MockAdapter.new({})
      @history_manager = HistoryManager.new(
        session_defaults: {
          max_messages: 100,
          max_tokens: 4000
        },
        persistence: { enabled: false }
      )
    end

    def test_compression_engine_with_history_manager
      session_id = "compression_test"
      
      # Add many messages to trigger compression
      20.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "This is message number #{i} with some content"
        })
      end
      
      session = @history_manager.get_session(session_id)
      assert_equal 20, session.message_count
      
      # Create compression engine and compress the session
      engine = CompressionEngine.new(
        llm_adapter: @mock_adapter,
        min_messages_to_compress: 5
      )
      
      result = engine.compress(session)
      assert result, "Compression should succeed"
      
      # Session should have fewer messages after compression
      assert session.message_count < 20, "Message count should be reduced"
      
      # Should have at least one summary message
      assert session.messages.any? { |msg| msg.is_summary }, "Should have summary message"
    end

    def test_summary_based_strategy_with_history_manager
      session_id = "strategy_test"
      
      # Add messages
      15.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "Message #{i}"
        })
      end
      
      session = @history_manager.get_session(session_id)
      
      # Create strategy and select messages
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: CompressionEngine.new(llm_adapter: @mock_adapter)
      )
      
      selected = strategy.select_messages(session.messages, nil)
      
      # Should have fewer messages than original
      assert selected.length < 15
      
      # Should include a summary
      assert selected.any? { |msg| msg.is_summary }
      
      # Should include recent messages
      recent_messages = session.messages.last(3)
      recent_messages.each do |msg|
        assert selected.include?(msg), "Should include recent message"
      end
    end

    def test_automatic_summarization_trigger
      session_id = "auto_summary_test"
      
      # Create strategy
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: CompressionEngine.new(llm_adapter: @mock_adapter)
      )
      
      # Add messages below threshold
      8.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "Message #{i}"
        })
      end
      
      session = @history_manager.get_session(session_id)
      refute strategy.should_compress?(session), "Should not compress below threshold"
      
      # Add more messages to exceed threshold
      5.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "Message #{i + 8}"
        })
      end
      
      session = @history_manager.get_session(session_id)
      assert strategy.should_compress?(session), "Should compress above threshold"
    end

    def test_compression_with_system_messages
      session_id = "system_test"
      
      # Add system message
      @history_manager.add_message(session_id, {
        role: "system",
        content: "You are a helpful assistant"
      })
      
      # Add many user messages
      20.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "Message #{i}"
        })
      end
      
      session = @history_manager.get_session(session_id)
      
      # Compress
      engine = CompressionEngine.new(llm_adapter: @mock_adapter)
      engine.compress(session)
      
      # System message should still be present
      assert session.messages.any?(&:system_message?), "System message should be preserved"
      assert_equal "system", session.messages.first.role
    end

    def test_token_limit_with_summaries
      session_id = "token_limit_test"
      
      # Add many messages
      20.times do |i|
        @history_manager.add_message(session_id, {
          role: "user",
          content: "This is a longer message #{i} with more content to increase token count"
        })
      end
      
      session = @history_manager.get_session(session_id)
      
      # Create strategy with token limit
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: CompressionEngine.new(llm_adapter: @mock_adapter)
      )
      
      # Select with token limit
      selected = strategy.select_messages(session.messages, 100)
      
      # Should respect token limit
      total_tokens = selected.sum { |msg| msg.token_count || 0 }
      assert total_tokens <= 100, "Should respect token limit"
    end
  end
end
