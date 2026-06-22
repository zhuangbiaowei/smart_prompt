require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"
require_relative "concerns/image_persistence"
require_relative "concerns/openai_chat_shaping"
require_relative "concerns/multimodal_messages"
require_relative "concerns/http_client"
require_relative "adapters/siliconflow/text"
require_relative "adapters/siliconflow/embed"
require_relative "adapters/siliconflow/image"
require_relative "adapters/siliconflow/video"
require_relative "adapters/siliconflow/voice"
require_relative "adapters/siliconflow/rerank"

module SmartPrompt
  # Adapter for 硅基流动 (SiliconFlow / SiliconCloud) — one adapter owns the whole
  # provider: every category shares the base URL https://api.siliconflow.cn/v1 and
  # Bearer auth.
  #
  # Per-modality behavior lives in capability modules under adapters/siliconflow/
  # (Text / Embed / Image / Video / Voice / Rerank); cross-provider plumbing (HTTP,
  # multimodal normalization, chat shaping, image saving) comes from the shared
  # concerns. This class wires them together + holds config/credentials.
  #
  # Provider-specific quirks (all vs https://docs.siliconflow.cn/cn/api-reference):
  #   chat/vision — POST {base}/chat/completions (reasoning_content, no remap)
  #   embeddings  — POST {base}/embeddings        (dimensions only for Qwen3-Embedding)
  #   rerank      — POST {base}/rerank            (results[].relevance_score)
  #   image/edit  — POST {base}/images/generations (images[].url; image_size/batch_size/guidance_scale)
  #   video       — POST {base}/video/submit -> POST {base}/video/status (async; results.videos[].url)
  #   tts         — POST {base}/audio/speech       (binary audio response)
  #   asr         — POST {base}/audio/transcriptions (multipart, field "file")
  #   voice       — /uploads/audio/voice, /audio/voice/list, /audio/voice/deletions
  class SiliconFlowAdapter < LLMAdapter
    DEFAULT_BASE_URL = "https://api.siliconflow.cn/v1".freeze

    # Cross-provider shared concerns
    include ImagePersistence
    include OpenAIChatShaping
    include MultimodalMessages
    include HTTPClient

    # Per-capability modules
    include SiliconFlow::Text
    include SiliconFlow::Embed
    include SiliconFlow::Image
    include SiliconFlow::Video
    include SiliconFlow::Voice
    include SiliconFlow::Rerank

    # ---- hooks for shared concerns -------------------------------------------
    def provider_label
      "SiliconFlow"
    end

    def default_image_prefix
      "siliconflow_image"
    end

    def initialize(config)
      super
      SmartPrompt.logger.info "Start create the SmartPrompt SiliconFlowAdapter."

      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      # Tolerate a missing key at construction (e.g. when the ENV var isn't set yet)
      # and let the first request fail with a clear auth error.
      SmartPrompt.logger.warn "SiliconFlow api_key is empty — API calls will fail until it is set." if api_key.nil? || api_key.to_s.strip.empty?

      @api_key  = api_key
      @base_url = (@config["url"] || DEFAULT_BASE_URL).to_s.chomp("/")
      # Optional per-method URL overrides (default to the standard paths off @base_url).
      @image_url         = (@config["image_url"]         || "#{@base_url}/images/generations").to_s
      @video_submit_url  = (@config["video_submit_url"]  || "#{@base_url}/video/submit").to_s
      @video_status_url  = (@config["video_status_url"]  || "#{@base_url}/video/status").to_s
      @speech_url        = (@config["speech_url"]        || "#{@base_url}/audio/speech").to_s
      @transcription_url = (@config["transcription_url"] || "#{@base_url}/audio/transcriptions").to_s
      @voice_upload_url  = (@config["voice_upload_url"]  || "#{@base_url}/uploads/audio/voice").to_s
      @voice_list_url    = (@config["voice_list_url"]    || "#{@base_url}/audio/voice/list").to_s
      @voice_delete_url  = (@config["voice_delete_url"]  || "#{@base_url}/audio/voice/deletions").to_s
      SmartPrompt.logger.info "SiliconFlow base_url=#{@base_url}"
    rescue => e
      SmartPrompt.logger.error "Failed to initialize SiliconFlow client: #{e.message}"
      raise e.is_a?(SmartPrompt::Error) ? e : LLMAPIError, "Invalid SiliconFlow configuration: #{e.message}"
    end
  end
end
