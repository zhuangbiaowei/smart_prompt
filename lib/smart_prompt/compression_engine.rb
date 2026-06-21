module SmartPrompt
  # CompressionEngine handles automatic compression of conversation history
  # through summarization using an LLM adapter
  # 
  # This engine:
  # - Generates summaries of older messages to reduce token usage
  # - Preserves key facts, decisions, and context in summaries
  # - Falls back to truncation strategies when summarization fails
  # - Tracks compression metrics for monitoring
  class CompressionEngine
    attr_reader :config

    # Initialize the compression engine
    # @param config [Hash] Configuration options
    # @option config [LLMAdapter] :llm_adapter LLM adapter for generating summaries
    # @option config [String] :prompt Custom summarization prompt template
    # @option config [Float] :compression_ratio (0.5) Target compression ratio
    # @option config [Integer] :min_messages_to_compress (5) Minimum messages needed for compression
    def initialize(config = {})
      @config = config
      @llm_adapter = config[:llm_adapter]
      @summarization_prompt = config[:prompt] || default_prompt
      @compression_ratio = config[:compression_ratio] || 0.5
      @min_messages_to_compress = config[:min_messages_to_compress] || 5
      @token_counter = TokenCounter.new
    end

    # Summarize a collection of messages into a single summary message
    # @param messages [Array<Message>] Messages to summarize
    # @return [Message, nil] Summary message or nil if summarization fails
    def summarize(messages)
      return nil if messages.nil? || messages.empty?
      return nil if messages.length < @min_messages_to_compress

      # Build the content to summarize
      content = messages.map { |msg| "#{msg.role}: #{msg.content}" }.join("\n")
      
      # Create the summarization prompt
      prompt = @summarization_prompt.gsub("{content}", content)

      begin
        # Call LLM to generate summary
        summary_text = if @llm_adapter
          @llm_adapter.send_request([
            { role: "user", content: prompt }
          ])
        else
          # If no LLM adapter, create a simple summary
          create_fallback_summary(messages)
        end

        # Calculate original token count
        original_tokens = messages.sum { |msg| msg.token_count || @token_counter.count(msg.content) }

        # Create summary message
        summary_message = Message.new(
          role: "system",
          content: "[Summary of previous conversation]\n#{summary_text}",
          is_summary: true,
          metadata: {
            original_count: messages.count,
            original_tokens: original_tokens,
            compressed_at: Time.now.iso8601
          }
        )

        # Calculate tokens for the summary
        summary_message.calculate_tokens(@token_counter)

        SmartPrompt.logger.info "Compressed #{messages.count} messages (#{original_tokens} tokens) " \
                                "into summary (#{summary_message.token_count} tokens)"

        summary_message
      rescue => e
        SmartPrompt.logger.error "Summarization failed: #{e.message}\n#{e.backtrace.join("\n")}"
        nil
      end
    end

    # Compress a session by identifying and summarizing compressible segments
    # @param session [Session] The session to compress
    # @return [Boolean] true if compression was successful
    def compress(session)
      return false if session.nil? || session.messages.empty?

      begin
        # Identify compressible message segments
        compressible_segments = identify_compressible_segments(session.messages)

        return false if compressible_segments.empty?

        # Generate summaries for each segment
        summaries = compressible_segments.map { |segment| summarize(segment) }.compact

        return false if summaries.empty?

        # Replace original messages with summaries
        replace_with_summaries(session, compressible_segments, summaries)

        SmartPrompt.logger.info "Session #{session.id} compressed: #{compressible_segments.flatten.count} " \
                                "messages replaced with #{summaries.count} summaries"
        true
      rescue => e
        SmartPrompt.logger.error "Compression failed for session #{session.id}: #{e.message}"
        
        # Fall back to truncation strategy
        fallback_truncate(session)
        false
      end
    end

    # Check if a session should be compressed based on configuration
    # @param session [Session] The session to evaluate
    # @return [Boolean] true if compression is recommended
    def should_compress?(session)
      return false if session.nil?
      
      # Check if session has enough messages to warrant compression
      session.message_count > (@min_messages_to_compress * 2)
    end

    private

    # Default summarization prompt template
    def default_prompt
      "Please provide a concise summary of the following conversation, " \
      "preserving key facts, decisions, and context. Focus on the most important " \
      "information that would be needed to continue the conversation:\n\n{content}"
    end

    # Create a simple fallback summary when LLM is not available
    # @param messages [Array<Message>] Messages to summarize
    # @return [String] Simple summary text
    def create_fallback_summary(messages)
      "Previous conversation contained #{messages.count} messages covering various topics."
    end

    # Identify segments of messages that can be compressed
    # Strategy: Keep recent messages, compress older ones
    # @param messages [Array<Message>] All messages in the session
    # @return [Array<Array<Message>>] Array of message segments to compress
    def identify_compressible_segments(messages)
      return [] if messages.length <= @min_messages_to_compress

      # Keep the most recent 5 messages uncompressed
      keep_recent = 5
      
      # Separate system messages (never compress) from others
      system_messages = messages.select(&:system_message?)
      non_system_messages = messages.reject(&:system_message?)

      # If we don't have enough non-system messages, don't compress
      return [] if non_system_messages.length <= keep_recent

      # Identify the older messages that can be compressed
      compressible = non_system_messages[0...-keep_recent]

      # Group into segments (for now, treat all compressible messages as one segment)
      compressible.empty? ? [] : [compressible]
    end

    # Replace original messages with summary messages in the session
    # @param session [Session] The session to modify
    # @param segments [Array<Array<Message>>] Original message segments
    # @param summaries [Array<Message>] Summary messages
    def replace_with_summaries(session, segments, summaries)
      # Get all messages to compress (flatten segments)
      messages_to_remove = segments.flatten

      # Remove the original messages
      session.messages.reject! { |msg| messages_to_remove.include?(msg) }

      # Insert summaries at the beginning (after system messages)
      system_messages = session.messages.select(&:system_message?)
      other_messages = session.messages.reject(&:system_message?)

      # Rebuild messages array: system messages + summaries + remaining messages
      session.instance_variable_set(:@messages, system_messages + summaries + other_messages)
      session.instance_variable_set(:@updated_at, Time.now)
    end

    # Fallback truncation strategy when summarization fails
    # Simply removes oldest non-system messages to reduce size
    # @param session [Session] The session to truncate
    def fallback_truncate(session)
      SmartPrompt.logger.warn "Falling back to truncation for session #{session.id}"

      # Keep system messages and recent messages
      system_messages = session.messages.select(&:system_message?)
      non_system_messages = session.messages.reject(&:system_message?)

      # Keep only the most recent half of non-system messages
      keep_count = (non_system_messages.length * 0.5).ceil
      kept_messages = non_system_messages.last(keep_count)

      # Update session messages
      session.instance_variable_set(:@messages, system_messages + kept_messages)
      session.instance_variable_set(:@updated_at, Time.now)
    end
  end
end
