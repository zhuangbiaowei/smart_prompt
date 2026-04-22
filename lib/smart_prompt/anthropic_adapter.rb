require "net/http"
require "json"
require "uri"

module SmartPrompt
  class AnthropicAdapter < LLMAdapter
    DEFAULT_URL = "https://api.anthropic.com"
    DEFAULT_VERSION = "2023-06-01"
    DEFAULT_MAX_TOKENS = 4096

    def initialize(config)
      super
      @api_key = resolve_api_key(@config["api_key"]) || ENV["ANTHROPIC_API_KEY"]
      @url = (@config["url"] || DEFAULT_URL).chomp("/")
      @anthropic_version = @config["anthropic_version"] || DEFAULT_VERSION
      @request_timeout = @config["request_timeout"] || 240

      raise LLMAPIError, "Invalid Anthropic configuration: missing api_key" if @api_key.nil? || @api_key.empty?

      @messages_uri = URI("#{@url}/v1/messages")
      SmartPrompt.logger.info "Successful creation an Anthropic client."
    rescue URI::InvalidURIError => e
      SmartPrompt.logger.error "Failed to initialize Anthropic client: #{e.message}"
      raise LLMAPIError, "Invalid Anthropic configuration: #{e.message}"
    rescue LLMAPIError
      raise
    rescue => e
      SmartPrompt.logger.error "Failed to initialize Anthropic client: #{e.message}"
      raise Error, "Unexpected error initializing Anthropic client: #{e.message}"
    end

    def send_request(messages, model = nil, temperature = 0.7, tools = nil, proc = nil)
      SmartPrompt.logger.info "AnthropicAdapter: Sending request to Anthropic"
      temperature = 0.7 if temperature.nil?
      model_name = model || @config["model"]
      SmartPrompt.logger.info "AnthropicAdapter: Using model #{model_name}"

      parameters = build_parameters(messages, model_name, temperature, tools, !proc.nil?)
      SmartPrompt.logger.info "Send parameters is: #{parameters}"

      response = post_messages(parameters, proc)
      SmartPrompt.logger.info "AnthropicAdapter: Received response from Anthropic"

      return if proc

      @last_response = response
      extract_content(response)
    rescue JSON::ParserError
      SmartPrompt.logger.error "Failed to parse Anthropic API response"
      raise LLMAPIError, "Failed to parse Anthropic API response"
    rescue LLMAPIError
      raise
    rescue => e
      SmartPrompt.logger.error "Unexpected error during Anthropic request: #{e.message}"
      raise Error, "Unexpected error during Anthropic request: #{e.message}"
    ensure
      SmartPrompt.logger.info "Successful send a message"
    end

    private

    def resolve_api_key(api_key)
      return api_key unless api_key.is_a?(String)

      match = api_key.match(/\AENV\[(["']?)([A-Za-z_][A-Za-z0-9_]*)\1\]\z/)
      return ENV[match[2]] if match

      api_key
    end

    def build_parameters(messages, model_name, temperature, tools, stream)
      anthropic_messages, system = normalize_messages(messages)
      parameters = {
        model: model_name,
        messages: anthropic_messages,
        max_tokens: @config["max_tokens"] || @config["max_completion_tokens"] || DEFAULT_MAX_TOKENS,
        temperature: @config["temperature"] || temperature,
      }
      parameters[:system] = system unless system.empty?
      parameters[:tools] = normalize_tools(tools) if tools
      parameters[:stream] = true if stream
      parameters
    end

    def normalize_messages(messages)
      system_messages = []
      anthropic_messages = []

      messages.each do |message|
        role = message["role"] || message[:role]
        content = message["content"] || message[:content]

        case role.to_s
        when "system"
          system_messages << content.to_s
        when "user", "assistant"
          anthropic_messages << {
            role: role.to_s,
            content: normalize_content(content),
          }
        when "tool"
          anthropic_messages << {
            role: "user",
            content: normalize_tool_result(message),
          }
        else
          anthropic_messages << {
            role: "user",
            content: normalize_content(content),
          }
        end
      end

      [anthropic_messages, system_messages.join("\n\n")]
    end

    def normalize_content(content)
      return content if content.is_a?(Array)

      content.to_s
    end

    def normalize_tool_result(message)
      tool_use_id = message["tool_call_id"] || message[:tool_call_id]
      content = message["content"] || message[:content]

      [{
        type: "tool_result",
        tool_use_id: tool_use_id.to_s,
        content: content.to_s,
      }]
    end

    def normalize_tools(tools)
      tools.map do |tool|
        function = tool["function"] || tool[:function] || tool
        {
          name: function["name"] || function[:name],
          description: function["description"] || function[:description],
          input_schema: function["parameters"] || function[:parameters] || {},
        }
      end
    end

    def post_messages(parameters, stream_proc)
      http = Net::HTTP.new(@messages_uri.host, @messages_uri.port)
      http.use_ssl = @messages_uri.scheme == "https"
      http.read_timeout = @request_timeout
      http.open_timeout = @request_timeout

      request = Net::HTTP::Post.new(@messages_uri)
      request["Content-Type"] = "application/json"
      request["x-api-key"] = @api_key
      request["anthropic-version"] = @anthropic_version
      request.body = JSON.generate(parameters)

      if stream_proc
        handle_streaming_response(http, request, stream_proc)
      else
        handle_response(http.request(request))
      end
    rescue SocketError => e
      SmartPrompt.logger.error "Failed to connect to Anthropic API: #{e.message}"
      raise LLMAPIError, "Network error: Unable to connect to Anthropic API"
    rescue Net::OpenTimeout, Net::ReadTimeout
      SmartPrompt.logger.error "Request to Anthropic API timed out"
      raise LLMAPIError, "Request to Anthropic API timed out"
    end

    def handle_response(response)
      body = JSON.parse(response.body)
      return body if response.is_a?(Net::HTTPSuccess)

      message = body.dig("error", "message") || response.message
      SmartPrompt.logger.error "Anthropic API error: #{message}"
      raise LLMAPIError, "Anthropic API error: #{message}"
    end

    def handle_streaming_response(http, request, stream_proc)
      accumulated_response = nil

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          body = response.body.to_s.empty? ? {} : JSON.parse(response.body)
          message = body.dig("error", "message") || response.message
          SmartPrompt.logger.error "Anthropic API error: #{message}"
          raise LLMAPIError, "Anthropic API error: #{message}"
        end

        response.read_body do |chunk|
          chunk.each_line do |line|
            next unless line.start_with?("data:")

            data = line.delete_prefix("data:").strip
            next if data.empty?

            event = JSON.parse(data)
            accumulated_response = event if event["type"] == "message_start"
            stream_proc.call(openai_stream_chunk(event), chunk.bytesize)
          end
        end
      end

      accumulated_response
    end

    def openai_stream_chunk(event)
      case event["type"]
      when "message_start"
        message = event["message"] || {}
        {
          "id" => message["id"],
          "object" => "chat.completion.chunk",
          "created" => Time.now.to_i,
          "model" => message["model"],
          "choices" => [{
            "index" => 0,
            "delta" => {},
          }],
          "usage" => message["usage"],
        }
      when "content_block_delta"
        {
          "choices" => [{
            "index" => 0,
            "delta" => {
              "content" => event.dig("delta", "text").to_s,
            },
          }],
        }
      else
        {
          "choices" => [{
            "index" => 0,
            "delta" => {},
          }],
        }
      end
    end

    def extract_content(response)
      response.fetch("content", []).map do |block|
        case block["type"]
        when "text"
          block["text"].to_s
        when "tool_use"
          block.to_s
        else
          block.to_s
        end
      end.join
    end
  end
end
