require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"

module SmartPrompt
  # Adapter for SenseNova (商汤 日日新) — the SenseCore large-model platform.
  #
  # One adapter owns the whole provider: all four documented model categories share the
  # same `api.sensenova.cn` domain and Bearer-token auth, so a single config block serves
  # them just by changing `model`.
  #
  #   1. 商量 文本对话 / 多模态 (chat + vision)  — OpenAI-compatible
  #        POST {url}/chat/completions     (url defaults to .../compatible-mode/v2)
  #        Streaming is SSE; the model may emit a `reasoning`/`delta.reasoning` field on
  #        reasoning models, which we remap to OpenAI's `reasoning_content` so the engine's
  #        stream aggregator (Engine#@stream_proc) keeps working unchanged.
  #   2. Cupido 向量模型 (embeddings)          — native, non-OpenAI response shape
  #        POST {embeddings_url}          (defaults to .../v1/llm/embeddings)
  #        Body {model, input:[...]}; response {embeddings:[{index, embedding, ...}]}.
  #   3. 秒画 文生图 (text-to-image)           — OpenAI-compatible /images/generations
  #        POST {image_url}  (native /v1 base, e.g. .../v1/images/generations;
  #        NOT under compatible-mode/v2, which 404s)
  #
  # We talk to the endpoints directly with Net::HTTP (like the image/tts/stt adapters)
  # rather than the `openai` gem, because we must surface SenseNova's `reasoning` field,
  # remap streaming deltas, and handle the native embeddings shape. No new gem deps.
  class SenseNovaAdapter < LLMAdapter
    DEFAULT_BASE_URL       = "https://api.sensenova.cn/compatible-mode/v2".freeze
    DEFAULT_EMBEDDINGS_URL = "https://api.sensenova.cn/v1/llm/embeddings".freeze
    # 秒画 text-to-image (sensenova-u1-fast) lives on the token.sensenova.cn /v1 base
    # (confirmed working 2026-06-19). NOT under compatible-mode/v2, which 404s.
    DEFAULT_IMAGE_URL      = "https://token.sensenova.cn/v1/images/generations".freeze
    # Sizes accepted by sensenova-u1-fast (the API 400s on anything else, e.g. 1024x1024).
    VALID_IMAGE_SIZES = %w[
      1664x2496 2496x1664 1760x2368 2368x1760 1824x2272 2272x1824
      2048x2048 2752x1536 1536x2752 3072x1376 1344x3136 2560x720 3072x864
    ].freeze
    DEFAULT_IMAGE_SIZE = "2048x2048".freeze
    SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif bmp webp].freeze

    # SenseNova sampling parameters forwarded from config to the chat request when present.
    CHAT_OPTIONAL_KEYS = %w[
      top_p top_k min_p presence_penalty frequency_penalty repetition_penalty
      reasoning_effort max_completion_tokens max_tokens
    ].freeze

    def initialize(config)
      super
      SmartPrompt.logger.info "Start create the SmartPrompt SenseNovaAdapter."

      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      # Match the other adapters: tolerate a missing key at construction (e.g. when the
      # ENV var isn't set yet) and let the first request fail with a clear auth error.
      SmartPrompt.logger.warn "SenseNova api_key is empty — API calls will fail until it is set." if api_key.nil? || api_key.to_s.strip.empty?

      @api_key        = api_key
      @base_url       = (@config["url"] || DEFAULT_BASE_URL).to_s.chomp("/")
      @embeddings_url = (@config["embeddings_url"] || DEFAULT_EMBEDDINGS_URL).to_s
      # 秒画 image generation lives on the native /v1 base (NOT compatible-mode/v2),
      # e.g. https://api.sensenova.cn/v1/images/generations. Override per-llm if needed.
      @image_url      = (@config["image_url"] || DEFAULT_IMAGE_URL).to_s
      SmartPrompt.logger.info "SenseNova base_url=#{@base_url}"
    rescue => e
      SmartPrompt.logger.error "Failed to initialize SenseNova client: #{e.message}"
      raise e.is_a?(SmartPrompt::Error) ? e : LLMAPIError, "Invalid SenseNova configuration: #{e.message}"
    end

    public

    # Chat / multimodal request.
    #
    # Non-streaming returns a full OpenAI-format hash (so last_response carries usage +
    # reasoning); streaming calls +proc+ with each OpenAI-shaped chunk and returns nil.
    def send_request(messages, model = nil, temperature = nil, tools = nil, proc = nil)
      model_name = model || @config["model"]
      body = build_chat_body(messages, model_name, temperature, tools)
      SmartPrompt.logger.info "SenseNovaAdapter: chat request model=#{model_name} stream=#{!proc.nil?}"

      if proc
        body["stream"] = true
        stream_chat("#{@base_url}/chat/completions", body) { |data| proc.call(build_stream_chunk(data), 0) }
        SmartPrompt.logger.info "SenseNovaAdapter: streaming request finished"
        nil
      else
        raw = http_post_json("#{@base_url}/chat/completions", body)
        response = build_completion_response(raw)
        @last_response = response
        SmartPrompt.logger.info "SenseNovaAdapter: received chat response"
        response
      end
    rescue LLMAPIError, Error
      raise
    rescue => e
      SmartPrompt.logger.error "SenseNova chat error: #{e.message}"
      raise LLMAPIError, "Failed to call SenseNova chat: #{e.message}"
    end

    # Cupido embeddings. SenseNova's native endpoint takes {model, input:[...]} and
    # returns {embeddings:[{index, embedding:[...], ...}]}; we surface the first vector.
    def embeddings(text, model)
      model_name = model || @config["embedding_model"] || @config["model"]
      SmartPrompt.logger.info "SenseNovaAdapter: embeddings model=#{model_name}"

      body = { "model" => model_name, "input" => [text.to_s] }
      response =
        begin
          http_post_json(@embeddings_url, body)
        rescue LLMAPIError, Error
          raise
        rescue => e
          raise LLMAPIError, "Failed to call SenseNova embeddings: #{e.message}"
        end

      items = response["embeddings"] || response["data"]
      unless items.is_a?(Array) && items.any? && items[0]["embedding"]
        raise LLMAPIError, "No embedding vector in SenseNova response: #{response.inspect}"
      end
      items[0]["embedding"]
    end

    # 秒画 text-to-image via the OpenAI-compatible /images/generations endpoint.
    # Response is parsed defensively (OpenAI `data[]` or SenseNova `images[]`).
    # Returns an Array of {url:, b64_json:, seed:}.
    def generate_image(prompt, params = {})
      SmartPrompt.logger.info "SenseNovaAdapter: generating image"
      raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?

      model_name = params[:model] || @config["image_model"] || @config["model"]
      raise Error, "No model configured for image generation" if model_name.nil? || model_name.to_s.strip.empty?

      body = { "model" => model_name, "prompt" => prompt.to_s }
      body["n"]                = params[:n]                if params[:n]
      body["size"]             = resolve_image_size(params[:size] || params[:image_size])
      body["response_format"]  = params[:response_format]  if params[:response_format]
      body["negative_prompt"]  = params[:negative_prompt]  if params[:negative_prompt]
      body["seed"]             = params[:seed]             if params[:seed]
      body["num_inference_steps"] = params[:num_inference_steps] if params[:num_inference_steps]
      body["guidance_scale"]      = params[:guidance_scale]      if params[:guidance_scale]

      SmartPrompt.logger.info "SenseNova image params: #{body.except('prompt').inspect}"

      response =
        begin
          http_post_json(@image_url, body)
        rescue LLMAPIError, Error
          raise
        rescue => e
          raise Error, "Failed to call SenseNova image generation: #{e.message}"
        end

      items = response["data"] || response["images"]
      unless items.is_a?(Array) && items.any?
        SmartPrompt.logger.error "SenseNova image response had no data: #{response.inspect}"
        raise LLMAPIError, "No image data in SenseNova response"
      end

      images = items.map do |d|
        { url: d["url"], b64_json: d["b64_json"], seed: d["seed"] }
      end
      SmartPrompt.logger.info "SenseNovaAdapter: generated #{images.size} image(s)"
      images
    end

    # Save one or many generated images to disk (Array from #generate_image or a single hash).
    def save_image(image_data, output_dir = "./output", filename_prefix = "sensenova_image")
      FileUtils.mkdir_p(output_dir)
      images = image_data.is_a?(Array) ? image_data : [image_data]
      saved = images.each_with_index.map do |img, index|
        save_single_image(img, output_dir, "#{filename_prefix}_#{index + 1}")
      end
      SmartPrompt.logger.info "Saved #{saved.size} SenseNova image(s) to #{output_dir}"
      saved
    end

    private

    # ---- chat request building ------------------------------------------------

    def build_chat_body(messages, model_name, temperature, tools)
      body = {
        "model"       => model_name,
        "messages"    => process_multimodal_messages(messages),
        "temperature" => @config["temperature"] || temperature || 0.7,
      }
      CHAT_OPTIONAL_KEYS.each { |k| body[k] = @config[k] if @config.key?(k) }
      body["tools"] = tools if tools && !tools.empty?
      body
    end

    # Pass messages through, normalizing any multimodal content. Local image paths inside
    # image_url.url are converted to data: URLs; http(s)/data URLs and plain text pass through.
    def process_multimodal_messages(messages)
      messages.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        content = content.map { |item| normalize_content_item(item) } if content.is_a?(Array)
        { "role" => role, "content" => content }
      end
    end

    def normalize_content_item(item)
      return { "type" => "text", "text" => item.to_s } unless item.is_a?(Hash)

      type = item[:type] || item["type"]
      if type == "image_url"
        iu = item[:image_url] || item["image_url"]
        url = iu.is_a?(Hash) ? (iu[:url] || iu["url"]) : iu
        { "type" => "image_url", "image_url" => { "url" => normalize_image_url(url) } }
      else
        stringify_hash(item)
      end
    end

    def normalize_image_url(url)
      return url if url.nil?
      return url if url.start_with?("http://", "https://", "data:")

      raise Error, "Image file not found: #{url}" unless File.exist?(url)
      ext = File.extname(url).downcase.delete(".")
      raise Error, "Unsupported image format: #{ext}" unless SUPPORTED_IMAGE_FORMATS.include?(ext)
      mime = ext == "jpg" ? "jpeg" : ext
      "data:image/#{mime};base64,#{Base64.strict_encode64(File.binread(url))}"
    end

    # ---- response shaping -----------------------------------------------------

    # Convert a non-streaming SenseNova response into the OpenAI completion shape the
    # rest of SmartPrompt expects, surfacing the reasoning model's `reasoning` field.
    def build_completion_response(raw)
      msg = raw.dig("choices", 0, "message") || {}
      message = { "role" => msg["role"] || "assistant" }
      message["content"] = msg["content"]
      message["reasoning_content"] = msg["reasoning"] if msg["reasoning"]
      message["tool_calls"] = msg["tool_calls"] if msg["tool_calls"]

      response = {
        "id"      => raw["id"],
        "object"  => raw["object"] || "chat.completion",
        "created" => raw["created"],
        "model"   => raw["model"],
        "choices" => [{
          "index"         => 0,
          "message"       => message,
          "finish_reason" => raw.dig("choices", 0, "finish_reason"),
        }],
      }
      response["usage"] = raw["usage"] if raw["usage"]
      response["system_fingerprint"] = raw["system_fingerprint"] if raw["system_fingerprint"]
      response
    end

    # Convert one SSE event from SenseNova's stream into an OpenAI-style streaming chunk.
    # The key remap is delta.reasoning -> delta.reasoning_content, which is what
    # Engine#@stream_proc reads for reasoning models.
    def build_stream_chunk(data)
      chunk = {
        "id"      => data["id"],
        "object"  => data["object"],
        "created" => data["created"],
        "model"   => data["model"],
      }
      chunk["usage"]             = data["usage"]             if data["usage"]
      chunk["system_fingerprint"] = data["system_fingerprint"] if data["system_fingerprint"]

      choices = data["choices"] || []
      if choices.any?
        delta = choices[0]["delta"] || {}
        new_delta = {}
        new_delta["role"]              = delta["role"]      if delta["role"]
        new_delta["content"]           = delta["content"]   if delta["content"]
        new_delta["reasoning_content"] = delta["reasoning"] if delta["reasoning"]
        new_delta["tool_calls"]        = delta["tool_calls"] if delta["tool_calls"]
        chunk["choices"] = [{
          "index"         => choices[0]["index"] || 0,
          "delta"         => new_delta,
          "finish_reason" => choices[0]["finish_reason"],
        }]
      else
        # Usage-only final event (choices is an empty array).
        chunk["choices"] = []
      end
      chunk
    end

    # ---- HTTP -----------------------------------------------------------------

    def http_post_json(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl     = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 240

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request.body = body.to_json

      SmartPrompt.logger.debug "SenseNova POST #{uri} body=#{body.to_json}"
      response = http.request(request)

      if response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body)
      else
        SmartPrompt.logger.error "SenseNova API error: #{response.code} - #{response.body}"
        raise LLMAPIError, "SenseNova API error: #{response.code} - #{response.body}"
      end
    end

    # POST with stream:true and yield each parsed SSE `data:` payload to the block.
    def stream_chat(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl      = (uri.scheme == "https")
      http.open_timeout  = 30
      http.read_timeout  = 300

      request = Net::HTTP::Post.new(uri.request_uri)
      request["Content-Type"]  = "application/json"
      request["Authorization"] = "Bearer #{@api_key}"
      request["Accept"]        = "text/event-stream"
      request.body = body.to_json

      buffer = ""
      done = false

      http.request(request) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise LLMAPIError, "SenseNova stream error: #{response.code} - #{response.body}"
        end

        response.read_body do |segment|
          break if done
          buffer << segment
          while (idx = buffer.index("\n"))
            line = buffer.slice!(0, idx + 1).strip
            next if line.empty? || !line.start_with?("data:")

            payload = line.sub(/\Adata:\s*/, "")
            if payload == "[DONE]"
              done = true
              break
            end

            begin
              data = JSON.parse(payload)
            rescue JSON::ParserError
              next
            end
            yield data
          end
        end
      end
    end

    # Resolve the image size: default to 2048x2048 when none given, and warn (but still
    # send) when the caller asks for a size sensenova-u1-fast does not accept.
    def resolve_image_size(size)
      return DEFAULT_IMAGE_SIZE if size.nil? || size.to_s.strip.empty?
      size = size.to_s
      unless VALID_IMAGE_SIZES.include?(size)
        SmartPrompt.logger.warn "SenseNova image size '#{size}' is not in the known-valid list " \
                                "(#{VALID_IMAGE_SIZES.join(', ')}); the API may reject it."
      end
      size
    end

    def save_single_image(image_data, output_dir, filename)
      if image_data[:b64_json]
        file_path = File.join(output_dir, "#{filename}.png")
        File.binwrite(file_path, Base64.decode64(image_data[:b64_json]))
      elsif image_data[:url]
        uri = URI.parse(image_data[:url])
        response = Net::HTTP.get_response(uri)
        raise Error, "Failed to download image from URL: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        ext = case response["content-type"]
              when "image/jpeg", "image/jpg" then "jpg"
              when "image/png"               then "png"
              when "image/gif"               then "gif"
              when "image/webp"              then "webp"
              else "png"
              end
        file_path = File.join(output_dir, "#{filename}.#{ext}")
        File.binwrite(file_path, response.body)
      else
        raise Error, "No image data available to save"
      end
      file_path
    end

    def stringify_hash(hash)
      case hash
      when Hash
        hash.each_with_object({}) do |(k, v), memo|
          memo[k.to_s] = stringify_hash(v)
        end
      when Array
        hash.map { |v| stringify_hash(v) }
      else
        hash
      end
    end
  end
end
