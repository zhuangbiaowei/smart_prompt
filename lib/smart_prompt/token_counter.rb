module SmartPrompt
  # TokenCounter provides token counting functionality with caching
  # Uses tiktoken for accurate token counting compatible with OpenAI models
  class TokenCounter
    def initialize(model: "gpt-3.5-turbo")
      @cache = {}
      @model = model
      @encoding = nil
      @use_tiktoken = load_tiktoken
    end

    # Count tokens in text with caching
    def count(text)
      return 0 if text.nil? || text.empty?
      
      # Return cached result if available
      return @cache[text] if @cache.key?(text)
      
      # Calculate and cache the result
      token_count = if @use_tiktoken
        count_with_tiktoken(text)
      else
        count_with_fallback(text)
      end
      
      @cache[text] = token_count
    end

    # Count tokens across multiple messages
    def count_messages(messages)
      return 0 if messages.nil? || messages.empty?
      
      messages.sum { |msg| count(msg.content) }
    end

    # Clear the cache
    def clear_cache
      @cache.clear
    end

    # Get cache size
    def cache_size
      @cache.size
    end

    private

    def load_tiktoken
      begin
        require 'tiktoken_ruby'
        @encoding = Tiktoken.encoding_for_model(@model)
        true
      rescue LoadError
        SmartPrompt.logger.warn "tiktoken_ruby not available, using fallback token counting"
        false
      rescue => e
        SmartPrompt.logger.warn "Failed to initialize tiktoken: #{e.message}, using fallback"
        false
      end
    end

    def count_with_tiktoken(text)
      @encoding.encode(text).length
    end

    # Fallback token counting using simple word-based estimation
    # Approximates ~1.3 tokens per word for English text
    def count_with_fallback(text)
      # Simple approximation: split by whitespace and punctuation
      words = text.scan(/\w+/)
      (words.length * 1.3).ceil
    end
  end
end
