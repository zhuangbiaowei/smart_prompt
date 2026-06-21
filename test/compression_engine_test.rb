require 'minitest/autorun'
require_relative '../lib/smart_prompt'

module SmartPrompt
  class CompressionEngineTest < Minitest::Test
    def setup
      @token_counter = TokenCounter.new
      @mock_adapter = MockAdapter.new({})
      @engine = CompressionEngine.new(
        llm_adapter: @mock_adapter,
        compression_ratio: 0.5,
        min_messages_to_compress: 3
      )
    end

    def test_summarize_with_sufficient_messages
      messages = create_messages(5)
      summary = @engine.summarize(messages)
      
      refute_nil summary
      assert summary.is_summary
      assert_equal "system", summary.role
      assert summary.content.include?("Summary")
      assert_equal 5, summary.metadata[:original_count]
    end

    def test_summarize_with_insufficient_messages
      messages = create_messages(2)
      summary = @engine.summarize(messages)
      
      assert_nil summary
    end

    def test_summarize_with_empty_array
      summary = @engine.summarize([])
      assert_nil summary
    end

    def test_summarize_with_nil
      summary = @engine.summarize(nil)
      assert_nil summary
    end

    def test_summarize_without_llm_adapter
      engine = CompressionEngine.new(llm_adapter: nil)
      messages = create_messages(5)
      summary = engine.summarize(messages)
      
      refute_nil summary
      assert summary.is_summary
      assert summary.content.include?("Previous conversation")
    end

    def test_compress_session_success
      session = Session.new("test", {})
      15.times { |i| session.add_message(role: "user", content: "Message #{i}") }
      
      initial_count = session.message_count
      result = @engine.compress(session)
      
      assert result
      assert session.message_count < initial_count
    end

    def test_compress_session_with_insufficient_messages
      session = Session.new("test", {})
      2.times { |i| session.add_message(role: "user", content: "Message #{i}") }
      
      result = @engine.compress(session)
      
      refute result
    end

    def test_should_compress_with_many_messages
      session = Session.new("test", {})
      10.times { session.add_message(role: "user", content: "Hello") }
      
      assert @engine.should_compress?(session)
    end

    def test_should_compress_with_few_messages
      session = Session.new("test", {})
      3.times { session.add_message(role: "user", content: "Hello") }
      
      refute @engine.should_compress?(session)
    end

    def test_fallback_on_llm_error
      # Create an adapter that raises an error
      error_adapter = Class.new(LLMAdapter) do
        def send_request(messages)
          raise "LLM Error"
        end
      end.new({})
      
      engine = CompressionEngine.new(llm_adapter: error_adapter)
      messages = create_messages(5)
      
      # Should return nil on error
      summary = engine.summarize(messages)
      assert_nil summary
    end

    def test_summary_metadata_includes_original_tokens
      messages = create_messages(5)
      summary = @engine.summarize(messages)
      
      refute_nil summary
      assert summary.metadata.key?(:original_tokens)
      assert summary.metadata[:original_tokens] > 0
    end

    def test_compression_preserves_system_messages
      session = Session.new("test", {})
      session.add_message(role: "system", content: "You are helpful")
      15.times { |i| session.add_message(role: "user", content: "Message #{i}") }
      
      @engine.compress(session)
      
      # System message should still be present
      assert session.messages.any?(&:system_message?)
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
