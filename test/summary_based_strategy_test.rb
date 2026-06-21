require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class SummaryBasedStrategyTest < Minitest::Test
    def setup
      @token_counter = TokenCounter.new
      @mock_adapter = MockAdapter.new({})
      @compression_engine = CompressionEngine.new(
        llm_adapter: @mock_adapter,
        min_messages_to_compress: 3
      )
      @strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: @compression_engine
      )
    end

    def test_select_messages_below_threshold
      messages = create_messages(5)
      result = @strategy.select_messages(messages, nil)
      
      assert_equal 5, result.length
      assert_equal messages, result
    end

    def test_select_messages_above_threshold_creates_summary
      messages = create_messages(15)
      result = @strategy.select_messages(messages, nil)
      
      # Should have summary + recent messages
      assert result.length < 15
      assert result.any? { |msg| msg.is_summary }
      
      # Should keep the most recent messages
      recent_messages = messages.last(3)
      recent_messages.each do |msg|
        assert result.include?(msg)
      end
    end

    def test_select_messages_with_empty_array
      result = @strategy.select_messages([], nil)
      assert_equal [], result
    end

    def test_select_messages_with_nil
      result = @strategy.select_messages(nil, nil)
      assert_equal [], result
    end

    def test_preserves_system_messages
      messages = []
      messages << create_message("system", "You are helpful")
      messages += create_messages(15, role: "user")
      
      result = @strategy.select_messages(messages, nil)
      
      # Should preserve system message
      assert result.any?(&:system_message?)
      assert_equal "system", result.first.role
    end

    def test_uses_existing_summaries
      messages = []
      messages << create_message("system", "You are helpful")
      
      # Add an existing summary
      summary = Message.new(
        role: "system",
        content: "[Summary] Previous conversation",
        is_summary: true
      )
      summary.calculate_tokens(@token_counter)
      messages << summary
      
      # Add recent messages
      messages += create_messages(5, role: "user")
      
      result = @strategy.select_messages(messages, nil)
      
      # Should use existing summary
      assert result.include?(summary)
    end

    def test_trim_to_token_limit
      messages = create_messages(15)
      result = @strategy.select_messages(messages, 50)
      
      # Should fit within token limit
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 50
    end

    def test_should_compress_above_threshold
      session = Session.new("test", {})
      15.times { session.add_message(role: "user", content: "Hello") }
      
      assert @strategy.should_compress?(session)
    end

    def test_should_compress_below_threshold
      session = Session.new("test", {})
      5.times { session.add_message(role: "user", content: "Hello") }
      
      refute @strategy.should_compress?(session)
    end

    def test_fallback_when_summarization_fails
      # Create a strategy with an engine that will fail
      error_adapter = Class.new(LLMAdapter) do
        def send_request(messages)
          raise "LLM Error"
        end
      end.new({})
      
      error_engine = CompressionEngine.new(llm_adapter: error_adapter)
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: error_engine
      )
      
      messages = create_messages(15)
      result = strategy.select_messages(messages, nil)
      
      # Should fall back to keeping recent messages
      refute_nil result
      assert result.length > 0
    end

    def test_configuration_summary_threshold
      strategy = SummaryBasedStrategy.new(summary_threshold: 5)
      messages = create_messages(6)
      result = strategy.select_messages(messages, nil)
      
      # Should trigger summarization at threshold of 5
      assert result.length < 6
    end

    def test_configuration_keep_recent
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 5,
        compression_engine: @compression_engine
      )
      
      messages = create_messages(15)
      result = strategy.select_messages(messages, nil)
      
      # Should keep 5 recent messages
      recent_messages = messages.last(5)
      recent_messages.each do |msg|
        assert result.include?(msg)
      end
    end

    def test_preserve_system_false
      strategy = SummaryBasedStrategy.new(
        summary_threshold: 10,
        keep_recent: 3,
        compression_engine: @compression_engine,
        preserve_system: false
      )
      
      messages = []
      messages << create_message("system", "System message")
      messages += create_messages(5, role: "user")
      
      result = strategy.select_messages(messages, nil)
      
      # System message should not be preserved
      refute result.any?(&:system_message?)
    end

    def test_token_limit_prioritizes_system_and_summaries
      messages = []
      messages << create_message("system", "System message")
      
      summary = Message.new(
        role: "system",
        content: "[Summary] Previous conversation",
        is_summary: true
      )
      summary.calculate_tokens(@token_counter)
      messages << summary
      
      messages += create_messages(10, role: "user")
      
      # Set a tight token limit
      result = @strategy.select_messages(messages, 30)
      
      # Should prioritize system message and summary
      assert result.any?(&:system_message?)
      assert result.any? { |msg| msg.is_summary }
    end

    private

    def create_messages(count, role: "user")
      count.times.map do |i|
        create_message(role, "Message #{i}")
      end
    end

    def create_message(role, content)
      msg = Message.new(role: role, content: content)
      msg.calculate_tokens(@token_counter)
      msg
    end
  end
end
