require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class RelevanceBasedStrategyIntegrationTest < Minitest::Test
    def setup
      @strategy = RelevanceBasedStrategy.new(
        top_k: 5,
        recency_weight: 0.3,
        relevance_weight: 0.7
      )
      @session = Session.new("test_session", {})
    end

    def test_strategy_works_with_session_messages
      # Add various messages to session
      @session.add_message(role: "system", content: "You are a helpful assistant")
      @session.add_message(role: "user", content: "Tell me about machine learning")
      @session.add_message(role: "assistant", content: "Machine learning is a subset of AI")
      @session.add_message(role: "user", content: "What about cats?")
      @session.add_message(role: "assistant", content: "Cats are wonderful pets")
      @session.add_message(role: "user", content: "Tell me about dogs")
      @session.add_message(role: "assistant", content: "Dogs are loyal companions")
      @session.add_message(role: "user", content: "Back to AI - what is deep learning?")
      
      # Create a current message about AI
      current_message = Message.new(
        role: "user",
        content: "Can you explain neural networks in machine learning?"
      )
      
      # Select messages using the strategy
      messages = @session.get_messages
      selected = @strategy.select_messages(messages, nil, current_message)
      
      # Should select top_k messages
      assert_equal 5, selected.length
      
      # Should maintain temporal order
      selected.each_cons(2) do |msg1, msg2|
        assert msg1.timestamp <= msg2.timestamp
      end
      
      # The messages about machine learning and AI should be prioritized
      # due to relevance, even if they're not the most recent
      selected_content = selected.map(&:content).join(" ")
      assert_includes selected_content, "machine learning", 
                      "Should include relevant messages about machine learning"
    end

    def test_strategy_respects_token_limits
      # Add many messages
      10.times do |i|
        @session.add_message(role: "user", content: "Message #{i} with some content here")
      end
      
      messages = @session.get_messages
      current = Message.new(role: "user", content: "test message")
      
      # Select with a tight token limit
      selected = @strategy.select_messages(messages, 50, current)
      
      # Verify token limit is respected
      total_tokens = selected.sum { |m| m.token_count || 0 }
      assert total_tokens <= 50, "Total tokens #{total_tokens} should not exceed 50"
    end

    def test_strategy_handles_empty_session
      messages = @session.get_messages
      current = Message.new(role: "user", content: "test")
      
      selected = @strategy.select_messages(messages, nil, current)
      assert_equal [], selected
    end

    def test_strategy_with_only_system_messages
      @session.add_message(role: "system", content: "You are a helpful assistant")
      @session.add_message(role: "system", content: "Be concise and clear")
      
      messages = @session.get_messages
      current = Message.new(role: "user", content: "Hello")
      
      selected = @strategy.select_messages(messages, nil, current)
      assert_equal 2, selected.length
      assert selected.all?(&:system_message?)
    end

    def test_compression_threshold_detection
      # Add messages below threshold
      10.times { @session.add_message(role: "user", content: "Message") }
      refute @strategy.should_compress?(@session)
      
      # Add more messages to exceed threshold (3 * top_k = 15)
      6.times { @session.add_message(role: "user", content: "Message") }
      assert @strategy.should_compress?(@session)
    end
  end
end
