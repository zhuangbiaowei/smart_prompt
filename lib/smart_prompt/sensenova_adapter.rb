require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"
require_relative "concerns/image_persistence"
require_relative "concerns/openai_chat_shaping"
require_relative "concerns/multimodal_messages"
require_relative "concerns/http_client"

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

    # SenseNova sampling parameters forwarded from config to the chat request when present.
    CHAT_OPTIONAL_KEYS = %w[
      top_p top_k min_p presence_penalty frequency_penalty repetition_penalty
      reasoning_effort max_completion_tokens max_tokens
    ].freeze

    include ImagePersistence
    include OpenAIChatShaping
    include MultimodalMessages
    include HTTPClient

    # ---- hooks for shared concerns -------------------------------------------
    def provider_label
      "SenseNova"
    end

    def default_image_prefix
      "sensenova_image"
    end

    # SenseNova exposes the reasoning trace under `reasoning` (not reasoning_content)
    # and also returns system_fingerprint — override the OpenAIChatShaping hooks so the
    # shared shaper still produces the uniform reasoning_content / fingerprint output.
    def reasoning_field_name
      "reasoning"
    end

    def extra_top_level_fields(raw)
      { "system_fingerprint" => raw["system_fingerprint"] }
    end

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

    # (save_image / save_single_image provided by ImagePersistence concern.)

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

    # (process_multimodal_messages / normalize_* / stringify_hash provided by MultimodalMessages concern.)
    # (build_completion_response / build_stream_chunk provided by OpenAIChatShaping concern.)

    # (http_post_json / stream_chat provided by HTTPClient concern.)

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

    # (stringify_hash provided by MultimodalMessages concern.)
  end
end
