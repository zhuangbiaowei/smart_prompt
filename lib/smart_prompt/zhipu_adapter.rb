require "base64"
require "json"
require "net/http"
require "uri"
require "fileutils"

module SmartPrompt
  # Adapter for 智谱 AI (BigModel / GLM) — covering all REST model categories behind one
  # provider domain. One adapter owns the whole provider: every category shares the same
  # base URL `https://open.bigmodel.cn/api/paas/v4` and Bearer-token auth, so a single config
  # block serves them just by changing `model`.
  #
  #   1. 文本对话 (chat)   — POST {base}/chat/completions      (OpenAI-compatible; reasoning
  #                          models return message.reasoning_content, the exact field the engine
  #                          already reads — no remap needed)
  #   2. 图文多模态 (vision) — same endpoint, OpenAI Vision content array
  #   3. 向量 (embeddings) — POST {base}/embeddings            (embedding-3, custom dimensions)
  #   4. 文生图 (image)    — POST {base}/images/generations    (response is NESTED: data.images[].url)
  #   5. 文生视频 (video)  — POST {base}/videos/generations -> task_id; GET {base}/async-result?task_id=
  #                          poll until SUCCESS -> video_result.url  (async)
  #   6. 语音合成 (TTS)    — POST {base}/audio/speech          (glm-tts)
  #   7. 语音识别 (ASR)    — POST {base}/audio/transcriptions  (glm-asr-2512, multipart)
  #   8. 重排 (rerank)     — POST {base}/rerank
  #
  # We talk to the endpoints with Net::HTTP directly (like the SenseNova / image / tts / stt /
  # video adapters) so we can control SSE streaming, the nested image shape, and the async
  # video flow. No new gem deps.
  class ZhipuAIAdapter < LLMAdapter
    DEFAULT_BASE_URL = "https://open.bigmodel.cn/api/paas/v4".freeze
    # CodeGeeX-4 / coding models use a separate base.
    DEFAULT_CODING_BASE_URL = "https://open.bigmodel.cn/api/coding/paas/v4".freeze
    SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif bmp webp].freeze

    # Zhipu chat sampling parameters forwarded from config when present.
    CHAT_OPTIONAL_KEYS = %w[
      top_p max_tokens do_sample stop presence_penalty frequency_penalty thinking
    ].freeze

    def initialize(config)
      super
      SmartPrompt.logger.info "Start create the SmartPrompt ZhipuAIAdapter."

      api_key = @config["api_key"]
      if api_key.is_a?(String) && api_key.start_with?("ENV[") && api_key.end_with?("]")
        api_key = eval(api_key)
      end
      # Match the other adapters: tolerate a missing key at construction so examples/config
      # can load without a live key; the first request fails with a clear auth error.
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

    public

    # ---- chat + vision -------------------------------------------------------

    # Chat / multimodal. Non-streaming returns a full OpenAI-format hash (so last_response
    # carries usage + reasoning_content); streaming calls +proc+ with each OpenAI-shaped chunk.
    def send_request(messages, model = nil, temperature = nil, tools = nil, proc = nil)
      model_name = model || @config["model"]
      body = build_chat_body(messages, model_name, temperature, tools)
      SmartPrompt.logger.info "ZhipuAIAdapter: chat request model=#{model_name} stream=#{!proc.nil?}"

      url = chat_url_for(model_name)
      if proc
        body["stream"] = true
        stream_chat(url, body) { |data| proc.call(build_stream_chunk(data), 0) }
        SmartPrompt.logger.info "ZhipuAIAdapter: streaming request finished"
        nil
      else
        raw = http_post_json(url, body)
        response = build_completion_response(raw)
        @last_response = response
        SmartPrompt.logger.info "ZhipuAIAdapter: received chat response"
        response
      end
    rescue LLMAPIError, Error
      raise
    rescue => e
      SmartPrompt.logger.error "Zhipu chat error: #{e.message}"
      raise LLMAPIError, "Failed to call Zhipu chat: #{e.message}"
    end

    # ---- embeddings ----------------------------------------------------------

    # embedding-3 (default 2048 dims); supports a custom `dimensions` (256/512/1024/2048)
    # via config. Returns the first embedding vector.
    def embeddings(text, model)
      model_name = model || @config["embedding_model"] || @config["model"]
      SmartPrompt.logger.info "ZhipuAIAdapter: embeddings model=#{model_name}"

      body = { "model" => model_name, "input" => text.is_a?(Array) ? text : [text.to_s] }
      body["dimensions"] = @config["dimensions"] if @config["dimensions"]
      body["encoding_format"] = @config["encoding_format"] if @config["encoding_format"]

      response =
        begin
          http_post_json("#{@base_url}/embeddings", body)
        rescue LLMAPIError, Error
          raise
        rescue => e
          raise LLMAPIError, "Failed to call Zhipu embeddings: #{e.message}"
        end

      items = response["data"]
      unless items.is_a?(Array) && items.any? && items[0]["embedding"]
        raise LLMAPIError, "No embedding vector in Zhipu response: #{response.inspect}"
      end
      items[0]["embedding"]
    end

    # ---- image (CogView / GLM-Image) -----------------------------------------

    # Text-to-image. The Zhipu response is NESTED: data.images[].url (not OpenAI's data[]),
    # so we parse defensively. Returns an Array of {url:, b64_json:}.
    def generate_image(prompt, params = {})
      SmartPrompt.logger.info "ZhipuAIAdapter: generating image"
      raise Error, "Prompt cannot be empty" if prompt.nil? || prompt.to_s.strip.empty?

      model_name = params[:model] || @config["image_model"] || @config["model"]
      raise Error, "No model configured for image generation" if model_name.nil? || model_name.to_s.strip.empty?

      body = { "model" => model_name, "prompt" => prompt.to_s }
      body["size"]            = params[:size]            if params[:size]
      body["user"]            = params[:user]            if params[:user]
      body["response_format"] = params[:response_format] if params[:response_format]

      SmartPrompt.logger.info "Zhipu image params: #{body.except('prompt').inspect}"
      response =
        begin
          http_post_json(@image_url, body)
        rescue LLMAPIError, Error
          raise
        rescue => e
          raise Error, "Failed to call Zhipu image generation: #{e.message}"
        end

      images = parse_image_response(response)
      SmartPrompt.logger.info "ZhipuAIAdapter: generated #{images.size} image(s)"
      images
    end

    # Save one or many generated images to disk (Array from #generate_image or a single hash).
    def save_image(image_data, output_dir = "./output", filename_prefix = "zhipu_image")
      FileUtils.mkdir_p(output_dir)
      images = image_data.is_a?(Array) ? image_data : [image_data]
      saved = images.each_with_index.map do |img, index|
        save_single_image(img, output_dir, "#{filename_prefix}_#{index + 1}")
      end
      SmartPrompt.logger.info "Saved #{saved.size} Zhipu image(s) to #{output_dir}"
      saved
    end

    # ---- video (CogVideoX, async) --------------------------------------------

    # Submit a text-to-video (or image-to-video) job. Returns the task id.
    def generate_video(prompt, params = {})
      SmartPrompt.logger.info "ZhipuAIAdapter: submitting video job"
      model_name = params[:model] || @config["video_model"] || @config["model"]
      raise Error, "No model configured for video generation" if model_name.nil? || model_name.to_s.strip.empty?

      body = { "model" => model_name, "prompt" => prompt.to_s }
      %i[quality fps duration with_audio resolution request_id seed].each do |k|
        body[k.to_s] = params[k] unless params[k].nil?
      end
      body["image_url"] = normalize_image_url(params[:image_url]) if params[:image_url]

      SmartPrompt.logger.info "Zhipu video params: #{body.except('prompt').inspect}"
      response =
        begin
          http_post_json(@video_url, body)
        rescue LLMAPIError, Error
          raise
        rescue => e
          raise Error, "Failed to submit Zhipu video job: #{e.message}"
        end

      task_id = response["id"] || response["task_id"]
      raise LLMAPIError, "No task id in Zhipu video response: #{response.inspect}" unless task_id
      SmartPrompt.logger.info "ZhipuAIAdapter: video task #{task_id} submitted"
      { task_id: task_id, model: model_name, raw: response }
    end

    # Poll an async task. Returns the raw status hash (task_status etc.).
    def check_video_status(task_id)
      SmartPrompt.logger.info "ZhipuAIAdapter: polling video task #{task_id}"
      http_get_json("#{@query_url}/#{URI.encode_www_form_component(task_id)}")
    rescue LLMAPIError, Error
      raise
    rescue => e
      raise LLMAPIError, "Failed to query Zhipu video task: #{e.message}"
    end

    # Block until the task finishes (or times out), then return the video URL.
    def wait_for_video_completion(task_id, check_interval: 10, timeout: 600)
      start = Time.now
      loop do
        status = check_video_status(task_id)
        case task_status_of(status)
        when "SUCCESS"
          url = video_url_of(status)
          raise LLMAPIError, "Video succeeded but no url in: #{status.inspect}" unless url
          SmartPrompt.logger.info "ZhipuAIAdapter: video ready #{url}"
          return { task_id: task_id, status: "SUCCESS", video_url: url, cover_image_url: cover_url_of(status), raw: status }
        when "FAIL", "FAILED"
          raise LLMAPIError, "Zhipu video generation failed: #{status.inspect}"
        else
          if Time.now - start > timeout
            raise LLMAPIError, "Zhipu video generation timeout after #{timeout}s"
          end
          SmartPrompt.logger.info "Zhipu video task #{task_id} still processing..."
          sleep(check_interval)
        end
      end
    end

    def download_video(video_url, output_path)
      uri = URI.parse(video_url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      response = http.request(Net::HTTP::Get.new(uri.request_uri))
      raise Error, "Failed to download video: #{response.code}" unless response.is_a?(Net::HTTPSuccess)
      FileUtils.mkdir_p(File.dirname(output_path))
      File.binwrite(output_path, response.body)
      SmartPrompt.logger.info "Zhipu video saved to #{output_path}"
      output_path
    rescue => e
      raise e.is_a?(SmartPrompt::Error) ? e : Error, "Error downloading Zhipu video: #{e.message}"
    end

    # ---- TTS (GLM-TTS) -------------------------------------------------------

    # Returns a base64 data URL for the synthesized audio. GLM-TTS accepts wav/pcm only
    # (mp3/flac are rejected), so default to wav.
    def synthesize_speech(text, voice: nil, model: nil, response_format: "wav", **opts)
      SmartPrompt.logger.info "ZhipuAIAdapter: TTS"
      raise Error, "Text cannot be empty" if text.nil? || text.to_s.strip.empty?

      model_name = model || @config["tts_model"] || "glm-tts"
      body = { "model" => model_name, "input" => text.to_s }
      body["voice"] = voice if voice
      body["response_format"] = response_format
      body["speed"] = opts[:speed] if opts[:speed]
      body["emotion"] = opts[:emotion] if opts[:emotion]

      audio = http_post_binary("#{@base_url}/audio/speech", body)
      "data:audio/#{response_format};base64,#{Base64.strict_encode64(audio)}"
    rescue LLMAPIError, Error
      raise
    rescue => e
      raise Error, "Failed to call Zhipu TTS: #{e.message}"
    end

    def synthesize_to_file(text, output_path, voice: nil, model: nil, response_format: "wav", **opts)
      data_url = synthesize_speech(text, voice: voice, model: model, response_format: response_format, **opts)
      FileUtils.mkdir_p(File.dirname(output_path))
      audio_bytes = Base64.decode64(data_url.sub(/\Adata:audio\/\w+;base64,/, ""))
      File.binwrite(output_path, audio_bytes)
      SmartPrompt.logger.info "Zhipu audio saved to #{output_path}"
      { file_path: output_path, format: response_format }
    end

    # ---- ASR (GLM-ASR-2512) --------------------------------------------------

    # Transcribe an audio file (local path). Returns {text:}.
    def transcribe_audio(audio_file, model: nil, language: nil, **opts)
      SmartPrompt.logger.info "ZhipuAIAdapter: ASR #{File.basename(audio_file)}"
      raise Error, "Audio file not found: #{audio_file}" unless File.exist?(audio_file)

      model_name = model || @config["asr_model"] || "glm-asr-2512"
      form = { "model" => model_name }
      form["language"] = language if language
      form["prompt"] = opts[:prompt] if opts[:prompt]
      form["response_format"] = opts[:response_format] if opts[:response_format]

      response = http_post_multipart("#{@base_url}/audio/transcriptions", form, audio_file)
      { text: response["text"] }
    rescue LLMAPIError, Error
      raise
    rescue => e
      raise e.is_a?(SmartPrompt::Error) ? e : Error, "Failed to call Zhipu ASR: #{e.message}"
    end

    # ---- rerank (bonus) ------------------------------------------------------

    def rerank(query, documents, model: nil)
      model_name = model || @config["rerank_model"] || @config["model"]
      body = { "model" => model_name, "query" => query, "documents" => documents }
      response = http_post_json("#{@base_url}/rerank", body)
      (response["results"] || []).map { |r| { index: r["index"], relevance_score: r["relevance_score"] || r["score"] } }
    rescue LLMAPIError, Error
      raise
    rescue => e
      raise LLMAPIError, "Failed to call Zhipu rerank: #{e.message}"
    end

    private

    # ---- chat building -------------------------------------------------------

    def chat_url_for(model_name)
      # CodeGeeX-4 and coding models are served from the coding base.
      (model_name.to_s.include?("codegeex") || @config["coding"]) ? "#{@coding_base}/chat/completions" : "#{@base_url}/chat/completions"
    end

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

    # Pass messages through, normalizing multimodal content (local image paths -> data URLs).
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

    # ---- response shaping ----------------------------------------------------

    # Zhipu's non-streaming chat response is already OpenAI-shaped; normalize to a consistent
    # hash and preserve reasoning_content where present.
    def build_completion_response(raw)
      msg = raw.dig("choices", 0, "message") || {}
      message = { "role" => msg["role"] || "assistant" }
      message["content"] = msg["content"]
      message["reasoning_content"] = msg["reasoning_content"] if msg["reasoning_content"]
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
      response
    end

    # Build an OpenAI-style streaming chunk from a Zhipu SSE event. reasoning_content and
    # content pass through unchanged (Zhipu already uses these names).
    def build_stream_chunk(data)
      chunk = {
        "id"      => data["id"],
        "object"  => data["object"],
        "created" => data["created"],
        "model"   => data["model"],
      }
      chunk["usage"] = data["usage"] if data["usage"]

      choices = data["choices"] || []
      if choices.any?
        delta = choices[0]["delta"] || {}
        new_delta = {}
        new_delta["role"]              = delta["role"]              if delta["role"]
        new_delta["content"]           = delta["content"]           if delta["content"]
        new_delta["reasoning_content"] = delta["reasoning_content"] if delta["reasoning_content"]
        new_delta["tool_calls"]        = delta["tool_calls"]        if delta["tool_calls"]
        chunk["choices"] = [{
          "index"         => choices[0]["index"] || 0,
          "delta"         => new_delta,
          "finish_reason" => choices[0]["finish_reason"],
        }]
      else
        chunk["choices"] = []
      end
      chunk
    end

    # Zhipu image response: cogview-3-flash returns the FLAT OpenAI shape data[].url;
    # older docs mention a NESTED data.images[].url. Handle both plus a bare-url array.
    def parse_image_response(response)
      container = response["data"]
      items =
        if container.is_a?(Hash)
          container["images"] || container["data"] || container["url"]
        elsif container.is_a?(Array)
          container
        end
      items ||= response["images"] || response["urls"]

      # Some responses return images as a bare array of URLs (strings).
      items = items.map { |x| x.is_a?(String) ? { "url" => x } : x } if items.is_a?(Array)

      unless items.is_a?(Array) && items.any?
        SmartPrompt.logger.error "Zhipu image response had no images: #{response.inspect}"
        raise LLMAPIError, "No image data in Zhipu response"
      end
      items.map { |d| { url: d["url"], b64_json: d["b64_json"] } }
    end

    # Zhipu async task status is under task_status; accept a few aliases.
    def task_status_of(status)
      status["task_status"] || status["status"] || "PROCESSING"
    end

    # video_result is an Array: [{cover_image_url:, url:}]. Pull the first video url.
    def video_url_of(status)
      vr = status["video_result"]
      item = vr.is_a?(Array) ? vr[0] : vr
      return item["url"] || item["video_url"] if item.is_a?(Hash)
      status["video_url"] || status.dig("data", "video_url")
    end

    def cover_url_of(status)
      vr = status["video_result"]
      item = vr.is_a?(Array) ? vr[0] : vr
      item.is_a?(Hash) ? (item["cover_image_url"] || item["cover_url"]) : nil
    end

    # ---- HTTP ----------------------------------------------------------------

    def http_post_json(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30; http.read_timeout = 240
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body.to_json
      SmartPrompt.logger.debug "Zhipu POST #{uri} body=#{body.to_json}"
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        SmartPrompt.logger.error "Zhipu API error: #{resp.code} - #{resp.body}"
        raise LLMAPIError, "Zhipu API error: #{resp.code} - #{resp.body}"
      end
    end

    def http_get_json(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30; http.read_timeout = 60
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      SmartPrompt.logger.debug "Zhipu GET #{uri}"
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        raise LLMAPIError, "Zhipu API error: #{resp.code} - #{resp.body}"
      end
    end

    # Returns the raw response body bytes (for TTS audio).
    def http_post_binary(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30; http.read_timeout = 120
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body.to_json
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body
      else
        raise LLMAPIError, "Zhipu TTS API error: #{resp.code} - #{resp.body}"
      end
    end

    # multipart/form-data POST with a file upload (for ASR). Returns parsed JSON.
    def http_post_multipart(url, form, file_path)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30; http.read_timeout = 180

      boundary = "----SmartPrompt#{object_id}"
      mime = "audio/#{(File.extname(file_path).downcase.delete(".") || "wav")}"

      body = ""
      form.each do |k, v|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"#{k}\"\r\n\r\n"
        body << "#{v}\r\n"
      end
      File.open(file_path, "rb") do |f|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"file\"; filename=\"#{File.basename(file_path)}\"\r\n"
        body << "Content-Type: #{mime}\r\n\r\n"
        body << f.read
        body << "\r\n"
      end
      body << "--#{boundary}--\r\n"

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "multipart/form-data; boundary=#{boundary}"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        raise LLMAPIError, "Zhipu ASR API error: #{resp.code} - #{resp.body}"
      end
    end

    # POST with stream:true and yield each parsed SSE `data:` payload to the block.
    def stream_chat(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port); http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30; http.read_timeout = 300

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"]        = "text/event-stream"
      req.body = body.to_json

      buffer = ""
      done = false
      http.request(req) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise LLMAPIError, "Zhipu stream error: #{response.code} - #{response.body}"
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
              yield JSON.parse(payload)
            rescue JSON::ParserError
              next
            end
          end
        end
      end
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
        hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = stringify_hash(v) }
      when Array
        hash.map { |v| stringify_hash(v) }
      else
        hash
      end
    end
  end
end
