require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"
require_relative "concerns/image_persistence"
require_relative "concerns/openai_chat_shaping"
require_relative "concerns/multimodal_messages"
require_relative "concerns/http_client"
require_relative "adapters/zhipu/text"
require_relative "adapters/zhipu/embed"
require_relative "adapters/zhipu/image"
require_relative "adapters/zhipu/video"
require_relative "adapters/zhipu/voice"
require_relative "adapters/zhipu/rerank"

module SmartPrompt
  # Adapter for 智谱 AI (BigModel / GLM) — one adapter owns the whole provider: every
  # category shares the base URL https://open.bigmodel.cn/api/paas/v4 and Bearer auth.
  #
  # Per-modality behavior lives in capability modules under adapters/zhipu/
  # (Text / Embed / Image / Video / Voice / Rerank); cross-provider plumbing (HTTP,
  # multimodal normalization, chat shaping, image saving) comes from the shared
  # concerns. This class wires them together + holds config/credentials.
  #
  #   chat/vision — POST {base}/chat/completions (OpenAI-compatible; reasoning_content)
  #   embeddings  — POST {base}/embeddings        (embedding-3, custom dimensions)
  #   image       — POST {base}/images/generations (nested data.images[].url)
  #   video       — POST {base}/videos/generations -> GET {base}/async-result (async)
  #   tts         — POST {base}/audio/speech       (glm-tts)
  #   asr         — POST {base}/audio/transcriptions (multipart)
  #   rerank      — POST {base}/rerank
  class ZhipuAIAdapter < LLMAdapter
    DEFAULT_BASE_URL = "https://open.bigmodel.cn/api/paas/v4".freeze
    # CodeGeeX-4 / coding models use a separate base.
    DEFAULT_CODING_BASE_URL = "https://open.bigmodel.cn/api/coding/paas/v4".freeze

    # Cross-provider shared concerns
    include ImagePersistence
    include OpenAIChatShaping
    include MultimodalMessages
    include HTTPClient

    # Per-capability modules
    include ZhipuAI::Text
    include ZhipuAI::Embed
    include ZhipuAI::Image
    include ZhipuAI::Video
    include ZhipuAI::Voice
    include ZhipuAI::Rerank

    # ---- hooks for shared concerns -------------------------------------------
    def provider_label
      "Zhipu"
    end

    def default_image_prefix
      "zhipu_image"
    end

    def initialize(config)
      super
      SmartPrompt.logger.info "Start create the SmartPrompt ZhipuAIAdapter."

      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      # Tolerate a missing key at construction so examples/config can load without a
      # live key; the first request fails with a clear auth error.
      SmartPrompt.logger.warn "Zhipu api_key is empty — API calls will fail until it is set." if api_key.nil? || api_key.to_s.strip.empty?

      @api_key     = api_key
      @base_url    = (@config["url"] || DEFAULT_BASE_URL).to_s.chomp("/")
      @coding_base = (@config["coding_url"] || DEFAULT_CODING_BASE_URL).to_s.chomp("/")
      # Optional per-method URL overrides (default to the standard paths off @base_url).
      @image_url  = (@config["image_url"]  || "#{@base_url}/images/generations").to_s
      @video_url  = (@config["video_url"]  || "#{@base_url}/videos/generations").to_s
      @query_url  = (@config["query_url"]  || "#{@base_url}/async-result").to_s
      SmartPrompt.logger.info "Zhipu base_url=#{@base_url}"
    end

    private

    # Zhipu's ASR call site uses the legacy 3-arg multipart shape (url, form, file_path).
    # Adapt it to HTTPClient's 5-arg shape with a sensible audio mime.
    def http_post_multipart(url, form, file_path)
      ext = File.extname(file_path).downcase.delete(".")
      super(url, form, "file", file_path, "audio/#{ext.empty? ? 'wav' : ext}")
    end
  end
end
