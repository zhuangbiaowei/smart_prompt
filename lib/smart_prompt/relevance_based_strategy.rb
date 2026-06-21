require_relative 'context_strategy'

module SmartPrompt
  # RelevanceBasedStrategy implements a context selection strategy based on
  # semantic relevance and importance scoring
  # 
  # This strategy:
  # - Calculates importance scores combining recency and relevance
  # - Selects top-k most important messages
  # - Supports both keyword-based and embedding-based similarity
  # - Maintains temporal ordering of selected messages
  # - Trims to token limits while preserving important context
  class RelevanceBasedStrategy
    include ContextStrategy

    # Initialize the relevance-based strategy
    # @param config [Hash] Configuration options
    # @option config [Integer] :top_k (10) Number of top messages to select
    # @option config [Float] :recency_weight (0.3) Weight for recency in scoring (0.0-1.0)
    # @option config [Float] :relevance_weight (0.7) Weight for relevance in scoring (0.0-1.0)
    # @option config [Object] :embedding_service (nil) Optional embedding service for semantic similarity
    def initialize(config = {})
      @top_k = config[:top_k] || 10
      @recency_weight = config[:recency_weight] || 0.3
      @relevance_weight = config[:relevance_weight] || 0.7
      @embedding_service = config[:embedding_service]
    end

    # Select messages based on relevance and importance
    # @param messages [Array<Message>] All messages in the session
    # @param max_tokens [Integer, nil] Maximum token limit for selected messages
    # @param current_message [Message, nil] The current message for relevance calculation
    # @return [Array<Message>] Selected messages ordered by timestamp
    def select_messages(messages, max_tokens, current_message = nil)
      return [] if messages.nil? || messages.empty?
      
      # If no current message, fall back to recency-only selection
      unless current_message
        log_debug "No current message provided, falling back to recency-based selection"
        return select_by_recency(messages, max_tokens)
      end

      # Calculate importance score for each message
      scored_messages = messages.map.with_index do |msg, idx|
        score = calculate_score(msg, idx, messages.length, current_message)
        [msg, score]
      end

      # Log top scores for debugging
      top_scores = scored_messages.sort_by { |_, score| -score }.take(5).map { |_, s| s.round(3) }
      log_debug "RelevanceBasedStrategy: calculated scores for #{messages.count} messages, top 5 scores: #{top_scores.inspect}"

      # Sort by score (descending) and take top-k
      selected = scored_messages
        .sort_by { |_, score| -score }
        .take(@top_k)
        .map(&:first)

      log_debug "RelevanceBasedStrategy: selected top #{selected.count}/#{messages.count} messages by importance (recency_weight=#{@recency_weight}, relevance_weight=#{@relevance_weight})"

      # Re-order by timestamp to maintain conversation flow
      selected = selected.sort_by(&:timestamp)

      # Trim to token limit if specified
      result = max_tokens ? trim_to_token_limit(selected, max_tokens) : selected
      
      if max_tokens && result.count < selected.count
        tokens_before = selected.sum { |m| m.token_count || 0 }
        tokens_after = result.sum { |m| m.token_count || 0 }
        log_debug "RelevanceBasedStrategy: trimmed to token limit #{max_tokens}: #{selected.count} -> #{result.count} messages, #{tokens_before} -> #{tokens_after} tokens"
      end
      
      result
    end

    # Determine if compression should be triggered
    # Recommends compression when message count exceeds 3x top_k
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if message count > 3 * top_k
    def should_compress?(session)
      session.message_count > @top_k * 3
    end

    private

    # Calculate combined importance score for a message
    # @param message [Message] The message to score
    # @param index [Integer] Position of message in the session
    # @param total [Integer] Total number of messages
    # @param current_message [Message] Current message for relevance comparison
    # @return [Float] Combined score (0.0-1.0)
    def calculate_score(message, index, total, current_message)
      # Calculate recency score (newer messages score higher)
      recency_score = total > 1 ? index.to_f / (total - 1) : 1.0

      # Calculate relevance score
      relevance_score = if @embedding_service
        calculate_semantic_similarity(message, current_message)
      else
        calculate_keyword_similarity(message, current_message)
      end

      # Combine scores with configured weights
      @recency_weight * recency_score + @relevance_weight * relevance_score
    end

    # Calculate semantic similarity using embeddings
    # @param msg1 [Message] First message
    # @param msg2 [Message] Second message
    # @return [Float] Cosine similarity (0.0-1.0)
    def calculate_semantic_similarity(msg1, msg2)
      begin
        emb1 = @embedding_service.get_embedding(msg1.content)
        emb2 = @embedding_service.get_embedding(msg2.content)
        cosine_similarity(emb1, emb2)
      rescue => e
        SmartPrompt.logger.warn "Embedding similarity failed: #{e.message}, falling back to keyword similarity"
        calculate_keyword_similarity(msg1, msg2)
      end
    end

    # Calculate keyword-based similarity using Jaccard index
    # @param msg1 [Message] First message
    # @param msg2 [Message] Second message
    # @return [Float] Jaccard similarity (0.0-1.0)
    def calculate_keyword_similarity(msg1, msg2)
      # Extract words and normalize
      words1 = extract_words(msg1.content)
      words2 = extract_words(msg2.content)

      # Handle empty content
      return 0.0 if words1.empty? || words2.empty?

      # Calculate Jaccard similarity: |intersection| / |union|
      intersection = (words1 & words2).length
      union = (words1 | words2).length

      union > 0 ? intersection.to_f / union : 0.0
    end

    # Extract and normalize words from text
    # @param text [String] Text to process
    # @return [Array<String>] Normalized words
    def extract_words(text)
      return [] if text.nil? || text.empty?
      
      # Convert to lowercase, extract words, remove common stop words
      words = text.downcase.scan(/\b\w+\b/)
      
      # Remove very short words (likely not meaningful)
      words.select { |w| w.length > 2 }
    end

    # Calculate cosine similarity between two vectors
    # @param vec1 [Array<Float>] First vector
    # @param vec2 [Array<Float>] Second vector
    # @return [Float] Cosine similarity (0.0-1.0)
    def cosine_similarity(vec1, vec2)
      return 0.0 if vec1.nil? || vec2.nil? || vec1.empty? || vec2.empty?
      return 0.0 if vec1.length != vec2.length

      # Calculate dot product
      dot_product = vec1.zip(vec2).map { |a, b| a * b }.sum

      # Calculate magnitudes
      magnitude1 = Math.sqrt(vec1.map { |x| x * x }.sum)
      magnitude2 = Math.sqrt(vec2.map { |x| x * x }.sum)

      # Avoid division by zero
      return 0.0 if magnitude1 == 0.0 || magnitude2 == 0.0

      # Return cosine similarity (normalized to 0-1 range)
      similarity = dot_product / (magnitude1 * magnitude2)
      
      # Clamp to [0, 1] range (cosine can be negative for opposite vectors)
      [[similarity, 0.0].max, 1.0].min
    end

    # Select messages by recency only (fallback when no current message)
    # @param messages [Array<Message>] All messages
    # @param max_tokens [Integer, nil] Maximum token limit
    # @return [Array<Message>] Most recent messages
    def select_by_recency(messages, max_tokens)
      selected = messages.last(@top_k)
      max_tokens ? trim_to_token_limit(selected, max_tokens) : selected
    end

    # Trim messages to fit within token limit
    # Removes messages from the beginning (oldest first) until within limit
    # @param messages [Array<Message>] Messages to trim
    # @param max_tokens [Integer] Maximum token limit
    # @return [Array<Message>] Trimmed messages
    def trim_to_token_limit(messages, max_tokens)
      return messages unless max_tokens
      return [] if messages.empty?

      # Calculate tokens from newest to oldest, keeping messages that fit
      total = 0
      selected = []

      messages.reverse_each do |msg|
        msg_tokens = msg.token_count || 0
        if total + msg_tokens <= max_tokens
          selected.unshift(msg)
          total += msg_tokens
        else
          # Stop adding messages once we exceed the limit
          break
        end
      end

      selected
    end
    
    # Logging helper methods
    def log_debug(message)
      return unless SmartPrompt.logger
      SmartPrompt.logger.debug "[RelevanceBasedStrategy] #{message}"
    end
  end
end
