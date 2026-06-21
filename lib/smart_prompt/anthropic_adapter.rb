require "anthropic"
require "base64"
require "uri"
require "json"

module SmartPrompt
  class AnthropicAdapter < LLMAdapter
    def initialize(config)
      super
      SmartPrompt.logger.info "Start create the SmartPrompt AnthropicAdapter."

      # Parse API key (support environment variable reference)
      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end

      # Determine base_url with priority: config['url'] > ENV['ANTHROPIC_BASE_URL'] > default
      base_url = @config["url"] || ENV["ANTHROPIC_BASE_URL"]

      begin
        # Create Anthropic::Client instance
        client_options = { api_key: api_key }
        client_options[:base_url] = base_url if base_url

        @client = Anthropic::Client.new(**client_options)
        SmartPrompt.logger.info "Successful creation an Anthropic client."
      rescue => e
        SmartPrompt.logger.error "Failed to initialize Anthropic client: #{e.message}"
        raise LLMAPIError, "Invalid Anthropic configuration: #{e.message}"
      end
    end

    private

    # Extract system message from messages array
    # @param messages [Array] Array of message hashes
    # @return [String, nil] System message content or nil if not found
    def extract_system_message(messages)
      system_msg = messages.find { |msg| msg[:role] == "system" || msg["role"] == "system" }
      system_msg ? (system_msg[:content] || system_msg["content"]) : nil
    end

    # Convert SmartPrompt message format to Anthropic format
    # @param messages [Array] Array of message hashes in SmartPrompt format
    # @return [Array] Array of message hashes in Anthropic format
    def convert_messages_to_anthropic_format(messages)
      messages.reject { |msg|
        role = msg[:role] || msg["role"]
        role == "system"
      }.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]

        # Convert content based on its type
        converted_content = if content.is_a?(String)
            # String content: convert to hash format
            { type: "text", text: content }
          elsif content.is_a?(Array)
            # Array content: process each item
            content.map do |item|
              item_type = item[:type] || item["type"]

              if item_type == "text"
                # Keep text items as-is
                item
              elsif item_type == "image_url"
                # Convert image_url to Anthropic format
                image_url = item[:image_url] || item["image_url"]
                url = image_url.is_a?(Hash) ? (image_url[:url] || image_url["url"]) : image_url
                prepare_image_content(url)
              else
                # Keep other types as-is
                item
              end
            end.compact # Remove nil values from failed image conversions
          else
            content
          end

        # String/scalar content becomes a single-element block array;
        # already-array (multimodal) content must not be double-wrapped.
        final_content = converted_content.is_a?(Array) ? converted_content : [converted_content]
        { role: role, content: final_content }
      end
    end

    # Prepare image content for Anthropic API
    # @param image_url [String] Image URL (HTTP/HTTPS or data URL)
    # @return [Hash, nil] Anthropic format image content or nil if invalid
    def prepare_image_content(image_url)
      return nil unless image_url.is_a?(String)

      if image_url.start_with?("http://", "https://")
        # HTTP/HTTPS URL format
        {
          type: "image",
          source: {
            type: "url",
            url: image_url,
          },
        }
      elsif image_url.start_with?("data:")
        # Data URL format: data:image/jpeg;base64,<base64_data>
        match = image_url.match(/^data:(image\/[^;]+);base64,(.+)$/)

        if match
          media_type = match[1]
          base64_data = match[2]

          {
            type: "image",
            source: {
              type: "base64",
              media_type: media_type,
              data: base64_data,
            },
          }
        else
          SmartPrompt.logger.warn "Invalid image URL format: #{image_url}"
          nil
        end
      else
        SmartPrompt.logger.warn "Invalid image URL format: #{image_url}"
        nil
      end
    end

    # Convert OpenAI format tools to Anthropic format
    # @param tools [Array, nil] Array of tool definitions in OpenAI format
    # @return [Array, nil] Array of tool definitions in Anthropic format or nil
    def convert_tools_to_anthropic_format(tools)
      # Handle nil or empty array
      return nil if tools.nil? || tools.empty?

      # Convert each tool definition
      tools.map do |tool|
        # Extract function field
        function = tool[:function] || tool["function"]
        next nil unless function

        # Extract name, description, and parameters
        name = function[:name] || function["name"]
        description = function[:description] || function["description"]
        parameters = function[:parameters] || function["parameters"]

        # Build Anthropic format tool definition
        {
          name: name,
          description: description,
          input_schema: parameters,
        }
      end.compact # Remove nil values from failed conversions
    end

    # Extract plain text from an Anthropic response's `content` field.
    # Handles a String, an Array of content blocks, nil, or an empty array.
    # @param response [Hash] Anthropic response (or its `content` value)
    # @return [String] Concatenated text, with multiple text blocks joined by newlines
    def extract_content_from_response(response)
      content = if response.is_a?(Hash)
                  response["content"] || response[:content]
                else
                  response
                end

      case content
      when String
        content
      when Array
        content.map do |block|
          next block unless block.is_a?(Hash)
          block["text"] || block[:text]
        end.compact.reject(&:empty?).join("\n")
      else
        content.to_s
      end
    end

    def convert_response_to_openai_format(response)
      begin
        # Normalize response to a Hash with symbol keys
        raw_response = if response.respond_to?(:to_h)
                         response.to_h
                       elsif response.is_a?(Hash)
                         response
                       else
                         JSON.parse(response.to_json)
                       end

        response_hash = deep_symbolize(raw_response)

        # Handle content blocks (text, tool_use, etc.)
        content_blocks = response_hash[:content] || []
        text_content = ""
        tool_calls = []

        case content_blocks
        when String
          text_content = content_blocks
        when Array
          content_blocks.each do |block|
            block_hash = block.respond_to?(:to_h) ? block.to_h : block
            block_hash = deep_symbolize(block_hash)
            next unless block_hash.is_a?(Hash)

            case block_hash[:type]
            when "text"
              text_content << block_hash[:text].to_s
            when "tool_use"
              tool_calls << {
                "index" => tool_calls.size,
                "id" => block_hash[:id] || "tool_call_#{tool_calls.size}",
                "type" => "function",
                "function" => {
                  "name" => block_hash[:name],
                  "arguments" => JSON.generate(block_hash[:input] || {}),
                },
              }
            end
          end
        else
          text_content = content_blocks.to_s
        end

        # Map stop reason to OpenAI finish_reason semantics
        stop_reason = response_hash[:stop_reason] || response_hash[:finish_reason]
        finish_reason = case stop_reason
                        when "tool_use"
                          "tool_calls"
                        when "end_turn", nil
                          "stop"
                        else
                          stop_reason
                        end

        # Map usage information
        usage = response_hash[:usage] || {}
        prompt_tokens = usage[:input_tokens]
        completion_tokens = usage[:output_tokens]
        cache_read_tokens = usage[:cache_read_input_tokens]
        cache_creation_tokens = usage[:cache_creation_input_tokens]
        total_tokens = if prompt_tokens || completion_tokens
                         [prompt_tokens, completion_tokens].compact.sum
                       end
        prompt_cache_hit_tokens = cache_read_tokens
        prompt_cache_miss_tokens = if prompt_tokens && cache_read_tokens
                                     prompt_tokens - cache_read_tokens
                                   end
        prompt_tokens_details = {}
        prompt_tokens_details["cached_tokens"] = cache_read_tokens if cache_read_tokens

        usage_hash = {}
        usage_hash["prompt_tokens"] = prompt_tokens if prompt_tokens
        usage_hash["completion_tokens"] = completion_tokens if completion_tokens
        usage_hash["total_tokens"] = total_tokens if total_tokens
        usage_hash["prompt_tokens_details"] = prompt_tokens_details unless prompt_tokens_details.empty?
        usage_hash["prompt_cache_hit_tokens"] = prompt_cache_hit_tokens if prompt_cache_hit_tokens
        usage_hash["prompt_cache_miss_tokens"] = prompt_cache_miss_tokens if prompt_cache_miss_tokens

        created_ts = response_hash[:created_at] || response_hash[:created] || Time.now.to_i

        message_role = response_hash[:role] || "assistant"

        openai_response = {
          "id" => response_hash[:id],
          "object" => "chat.completion",
          "created" => created_ts,
          "model" => response_hash[:model],
          "choices" => [
            {
              "index" => 0,
              "message" => {
                "role" => message_role,
                "content" => text_content.empty? ? nil : text_content,
              },
              "finish_reason" => finish_reason,
            },
          ],
        }

        unless tool_calls.empty?
          openai_response["choices"][0]["message"]["tool_calls"] = tool_calls
        end

        openai_response["usage"] = usage_hash unless usage_hash.empty?
        openai_response["system_fingerprint"] = response_hash[:system_fingerprint] if response_hash[:system_fingerprint]

        @last_response = openai_response
        openai_response
      rescue => e
        SmartPrompt.logger.error "Failed to convert Anthropic response: #{e.message}"
        raise LLMAPIError, "Failed to convert Anthropic response: #{e.message}"
      end
    end

    # Deeply symbolize hash keys for consistent access
    def deep_symbolize(obj)
      case obj
      when Hash
        obj.each_with_object({}) do |(k, v), memo|
          key = k.is_a?(String) || k.is_a?(Symbol) ? k.to_sym : k
          memo[key] = deep_symbolize(v)
        end
      when Array
        obj.map { |item| deep_symbolize(item) }
      else
        obj
      end
    end

    public

    # Send request to Anthropic API
    # @param messages [Array] Array of message hashes
    # @param model [String, nil] Model name (optional, uses config default if nil)
    # @param temperature [Float, nil] Temperature value (optional, uses config or 0.7 if nil)
    # @param tools [Array, nil] Array of tool definitions (optional)
    # @param proc [Proc, nil] Callback for streaming responses (optional)
    # @return [Hash, nil] OpenAI-formatted response (nil for streaming mode)
    def send_request(messages, model = nil, temperature = nil, tools = nil, proc = nil)
      begin
        # Determine model name (parameter > config)
        model_name = model || @config["model"]

        # Determine temperature (config > parameter > default 0.7)
        temp_value = @config["temperature"] || temperature || 0.7

        # Determine max_tokens (config > default 1024)
        max_tokens_value = @config["max_tokens"] || 1024

        SmartPrompt.logger.info "AnthropicAdapter: Sending request to Anthropic"
        SmartPrompt.logger.info "AnthropicAdapter: Using model #{model_name}"

        # Extract system message
        system_message = extract_system_message(messages)

        # Convert messages to Anthropic format
        converted_messages = convert_messages_to_anthropic_format(messages)

        # Build request parameters
        parameters = {
          model: model_name,
          messages: converted_messages,
          max_tokens: max_tokens_value,
          temperature: temp_value,
        }

        # Add system message if present
        parameters[:system] = system_message if system_message

        # Convert and add tools if provided
        if tools
          anthropic_tools = convert_tools_to_anthropic_format(tools)
          parameters[:tools] = anthropic_tools if anthropic_tools
        end

        SmartPrompt.logger.info "Send parameters is: #{parameters}"

        # Send request to Anthropic API
        if proc
          # Streaming mode: use stream method
          stream = @client.messages.stream(**parameters)

          # Iterate through the stream and call proc for each event
          stream.each do |event|
            # Convert event to hash format for compatibility
            event_hash = {
              "type" => event.type.to_s,
            }

            # Add delta information for content_block_delta events
            if event.type == :content_block_delta && event.delta.type == :text_delta
              event_hash["delta"] = { "text" => event.delta.text }
            end

            proc.call(event_hash, 0)
          end

          SmartPrompt.logger.info "Successful send a message (streaming)"
          nil
        else
          # Non-streaming mode: use create method
          response = @client.messages.create(**parameters)
          SmartPrompt.logger.info "Successful send a message"
          SmartPrompt.logger.info "AnthropicAdapter: Received response from Anthropic"

          # Convert response to openai format
          convert_response_to_openai_format(response)
        end
      rescue => e
        SmartPrompt.logger.error "Anthropic API error: #{e.message}"
        SmartPrompt.logger.error "Error class: #{e.class}"
        SmartPrompt.logger.error "Backtrace: #{e.backtrace.first(5).join("\n")}"
        raise LLMAPIError, "Failed to send request to Anthropic: #{e.message}"
      end
    end

    # Embeddings method (not supported by Anthropic API)
    # @param text [String] Text to generate embeddings for
    # @param model [String] Model name
    # @raise [NotImplementedError] Always raises as Anthropic doesn't support embeddings
    def embeddings(text, model)
      raise NotImplementedError, "Anthropic API does not support embeddings. Please use OpenAI or other providers for embedding generation."
    end
  end
end
