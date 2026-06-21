require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class RelevanceBasedStrategyTest < Minitest::Test
    def setup
      @strategy = RelevanceBasedStrategy.new(top_k: 5, recency_weight: 0.3, relevance_weight: 0.7)
      @token_counter = TokenCounter.new
    end

    def test_select_messages_with_empty_array
      result = @strategy.select_messages([], nil, nil)
      assert_equal [], result
    end

    def test_select_messages_without_current_message_falls_back_to_recency
      messages = create_messages(10)
      result = @strategy.select_messages(messages, nil, nil)
      
      # Should select top_k most recent messages
      assert_equal 5, result.length
      assert_equal messages[-5..-1], result
    end

    def test_select_messages_with_current_message_uses_relevance
      messages = []
      messages << create_message("user", "I love machine learning and AI")
      messages << create_message("assistant", "That's great!")
      messages << create_message("user", "Tell me about cats")
      messages << create_message("assistant", "Cats are wonderful pets")
      messages << create_message("user", "What about dogs?")
      messages << create_message("assistant", "Dogs are loyal companions")
      
      current = create_message("user", "Can you explain more about machine learning?")
      
      result = @strategy.select_messages(messages, nil, current)
      
      # Should select top_k messages
      assert_equal 5, result.length
      
      # Should maintain temporal order
      result.each_cons(2) do |msg1, msg2|
        assert msg1.timestamp <= msg2.timestamp, "Messages should be ordered by timestamp"
      end
    end

    def test_keyword_similarity_calculation
      msg1 = create_message("user", "machine learning is fascinating")
      msg2 = create_message("user", "I love machine learning")
      msg3 = create_message("user", "cats are cute")
      
      # Messages with overlapping keywords should have higher similarity
      similarity_high = @strategy.send(:calculate_keyword_similarity, msg1, msg2)
      similarity_low = @strategy.send(:calculate_keyword_similarity, msg1, msg3)
      
      assert similarity_high > similarity_low, "Related messages should have higher similarity"
      assert similarity_high > 0, "Similar messages should have positive similarity"
      assert similarity_high <= 1.0, "Similarity should not exceed 1.0"
    end

    def test_keyword_similarity_with_empty_content
      msg1 = create_message("user", "")
      msg2 = create_message("user", "hello world")
      
      similarity = @strategy.send(:calculate_keyword_similarity, msg1, msg2)
      assert_equal 0.0, similarity, "Empty content should have zero similarity"
    end

    def test_extract_words_normalizes_and_filters
      words = @strategy.send(:extract_words, "Hello World! This is a TEST.")
      
      # Should be lowercase
      assert words.all? { |w| w == w.downcase }, "Words should be lowercase"
      
      # Should filter short words (length <= 2)
      assert words.none? { |w| w.length <= 2 }, "Short words should be filtered"
      
      # Should extract meaningful words
      assert_includes words, "hello"
      assert_includes words, "world"
      assert_includes words, "test"
    end

    def test_cosine_similarity_calculation
      vec1 = [1.0, 0.0, 0.0]
      vec2 = [1.0, 0.0, 0.0]
      vec3 = [0.0, 1.0, 0.0]
      
      # Identical vectors should have similarity 1.0
      similarity_identical = @strategy.send(:cosine_similarity, vec1, vec2)
      assert_in_delta 1.0, similarity_identical, 0.001
      
      # Orthogonal vectors should have similarity 0.0
      similarity_orthogonal = @strategy.send(:cosine_similarity, vec1, vec3)
      assert_in_delta 0.0, similarity_orthogonal, 0.001
    end

    def test_cosine_similarity_with_invalid_inputs
      assert_equal 0.0, @strategy.send(:cosine_similarity, nil, [1.0])
      assert_equal 0.0, @strategy.send(:cosine_similarity, [1.0], nil)
      assert_equal 0.0, @strategy.send(:cosine_similarity, [], [1.0])
      assert_equal 0.0, @strategy.send(:cosine_similarity, [1.0], [1.0, 2.0])
    end

    def test_trim_to_token_limit
      messages = create_messages(10)
      
      # Trim to a small token limit
      result = @strategy.send(:trim_to_token_limit, messages, 25)
      
      # Should only include messages that fit within token limit
      assert result.length <= 10
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 25, "Total tokens #{total_tokens} should not exceed limit 25"
    end

    def test_trim_to_token_limit_with_zero_limit
      messages = create_messages(5)
      result = @strategy.send(:trim_to_token_limit, messages, 0)
      assert_equal [], result, "Zero token limit should return empty array"
    end

    def test_should_compress_when_exceeds_threshold
      session = Session.new("test", {})
      
      # Add messages below threshold (3 * top_k = 15)
      10.times { session.add_message(role: "user", content: "Hello") }
      refute @strategy.should_compress?(session), "Should not compress below threshold"
      
      # Add messages above threshold
      6.times { session.add_message(role: "user", content: "Hello") }
      assert @strategy.should_compress?(session), "Should compress above threshold"
    end

    def test_top_k_configuration
      strategy = RelevanceBasedStrategy.new(top_k: 3)
      messages = create_messages(10)
      
      result = strategy.select_messages(messages, nil, nil)
      assert_equal 3, result.length, "Should respect top_k configuration"
    end

    def test_recency_weight_affects_scoring
      # Create strategy with high recency weight
      strategy_recency = RelevanceBasedStrategy.new(
        top_k: 3,
        recency_weight: 0.9,
        relevance_weight: 0.1
      )
      
      messages = []
      messages << create_message("user", "machine learning is great")
      messages << create_message("user", "cats are cute")
      messages << create_message("user", "dogs are loyal")
      
      current = create_message("user", "tell me about machine learning")
      
      result = strategy_recency.select_messages(messages, nil, current)
      
      # With high recency weight, should prefer recent messages
      assert_equal 3, result.length
      # Most recent message should be included
      assert_includes result, messages[-1]
    end

    def test_maintains_temporal_order_after_selection
      messages = create_messages(20)
      current = create_message("user", "test message")
      
      result = @strategy.select_messages(messages, nil, current)
      
      # Verify temporal ordering
      result.each_cons(2) do |msg1, msg2|
        assert msg1.timestamp <= msg2.timestamp, 
               "Messages should maintain temporal order"
      end
    end

    def test_handles_messages_with_nil_token_count
      messages = []
      3.times do |i|
        msg = Message.new(role: "user", content: "Message #{i}")
        # Don't calculate tokens - leave as nil
        messages << msg
      end
      
      # Should handle gracefully without crashing
      result = @strategy.select_messages(messages, 100, nil)
      assert_equal 3, result.length
    end

    def test_select_messages_respects_max_tokens
      messages = create_messages(10)
      current = create_message("user", "test")
      
      result = @strategy.select_messages(messages, 30, current)
      
      total_tokens = result.sum { |m| m.token_count || 0 }
      assert total_tokens <= 30, "Should respect max_tokens limit"
    end

    def test_embedding_service_fallback_on_error
      # Create a mock embedding service that raises an error.
      # (Plain stub instead of Minitest::Mock — removed in minitest 6.)
      mock_service = Object.new
      def mock_service.get_embedding(_content)
        raise "Embedding service error"
      end
      
      strategy = RelevanceBasedStrategy.new(
        top_k: 5,
        embedding_service: mock_service
      )
      
      msg1 = create_message("user", "hello world")
      msg2 = create_message("user", "hello there")
      
      # Should fall back to keyword similarity without crashing
      similarity = strategy.send(:calculate_semantic_similarity, msg1, msg2)
      
      # Should return a valid similarity score
      assert similarity >= 0.0
      assert similarity <= 1.0
    end

    private

    def create_messages(count, role: "user")
      count.times.map do |i|
        create_message(role, "Message #{i} with some content")
      end
    end

    def create_message(role, content)
      msg = Message.new(role: role, content: content)
      msg.calculate_tokens(@token_counter)
      msg
    end
  end
end
