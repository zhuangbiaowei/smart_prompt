module SmartPrompt
  module ZhipuAI
    # Speech synthesis (GLM-TTS) + speech recognition (GLM-ASR-2512).
    module Voice
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
    end
  end
end
