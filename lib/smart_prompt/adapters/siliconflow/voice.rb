module SmartPrompt
  module SiliconFlow
    # Speech synthesis (CosyVoice2 / MOSS-TTSD), speech recognition (SenseVoiceSmall),
    # and custom-voice cloning management.
    module Voice
      # Returns a base64 data URL for the synthesized audio. SiliconFlow's
      # /audio/speech returns the raw binary audio stream (NOT base64 / NOT JSON),
      # so we base64-encode it ourselves.
      def synthesize_speech(text, voice: nil, model: nil, response_format: "mp3", **opts)
        SmartPrompt.logger.info "SiliconFlowAdapter: TTS"
        raise Error, "Text cannot be empty" if text.nil? || text.to_s.strip.empty?

        model_name = model || @config["tts_model"] || "FunAudioLLM/CosyVoice2-0.5B"
        body = { "model" => model_name, "input" => text.to_s }
        body["voice"]           = voice            if voice
        body["response_format"] = response_format
        body["speed"]           = opts[:speed]           if opts[:speed]
        body["sample_rate"]     = opts[:sample_rate]     if opts[:sample_rate]
        body["gain"]            = opts[:gain]            if opts[:gain]
        body["language"]        = opts[:language]        if opts[:language]

        audio = http_post_binary(@speech_url, body)
        "data:audio/#{response_format};base64,#{Base64.strict_encode64(audio)}"
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise Error, "Failed to call SiliconFlow TTS: #{e.message}"
      end

      def synthesize_to_file(text, output_path, voice: nil, model: nil, response_format: "mp3", **opts)
        data_url = synthesize_speech(text, voice: voice, model: model, response_format: response_format, **opts)
        FileUtils.mkdir_p(File.dirname(output_path))
        audio_bytes = Base64.decode64(data_url.sub(/\Adata:audio\/\w+;base64,/, ""))
        File.binwrite(output_path, audio_bytes)
        SmartPrompt.logger.info "SiliconFlow audio saved to #{output_path}"
        { file_path: output_path, format: response_format }
      end

      # Transcribe an audio file (local path). Returns {text:}. The transcription
      # endpoint takes multipart/form-data with a `file` field.
      def transcribe_audio(audio_file, model: nil, language: nil, **opts)
        SmartPrompt.logger.info "SiliconFlowAdapter: ASR #{File.basename(audio_file)}"
        raise Error, "Audio file not found: #{audio_file}" unless File.exist?(audio_file)

        model_name = model || @config["asr_model"] || "FunAudioLLM/SenseVoiceSmall"
        form = { "model" => model_name }
        form["language"]         = language if language
        form["prompt"]           = opts[:prompt]           if opts[:prompt]
        form["response_format"]  = opts[:response_format]  if opts[:response_format]

        mime = "audio/#{File.extname(audio_file).downcase.delete(".") || "wav"}"
        response = http_post_multipart(@transcription_url, form, "file", audio_file, mime)
        { text: response["text"] }
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise e.is_a?(SmartPrompt::Error) ? e : Error, "Failed to call SiliconFlow ASR: #{e.message}"
      end

      # Upload a reference audio to clone a custom voice. SiliconFlow returns
      # {"uri": "speech:..."}. `customName` (camelCase) is the display name.
      def upload_voice(name, audio_file, text: nil, model: nil)
        SmartPrompt.logger.info "SiliconFlowAdapter: upload voice #{name}"
        raise Error, "Audio file not found: #{audio_file}" unless File.exist?(audio_file)

        model_name = model || @config["tts_model"] || "FunAudioLLM/CosyVoice2-0.5B"
        form = { "model" => model_name, "customName" => name.to_s }
        form["text"] = text.to_s if text
        mime = "audio/#{File.extname(audio_file).downcase.delete(".") || "wav"}"
        response = http_post_multipart(@voice_upload_url, form, "file", audio_file, mime)
        raise LLMAPIError, "No uri in SiliconFlow voice upload response: #{response.inspect}" unless response["uri"]
        { uri: response["uri"], name: name.to_s, raw: response }
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise e.is_a?(SmartPrompt::Error) ? e : Error, "Failed to upload SiliconFlow voice: #{e.message}"
      end

      def list_voices
        SmartPrompt.logger.info "SiliconFlowAdapter: list voices"
        response = http_get_json(@voice_list_url)
        (response["result"] || response["voices"] || response).yield_self do |items|
          items.is_a?(Array) ? items.map { |v| { uri: v["uri"], name: v["customName"] || v["name"] } } : response
        end
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise LLMAPIError, "Failed to list SiliconFlow voices: #{e.message}"
      end

      def delete_voice(uri)
        SmartPrompt.logger.info "SiliconFlowAdapter: delete voice #{uri}"
        response = http_post_json(@voice_delete_url, { "uri" => uri })
        { deleted: response["deleted"].nil? ? true : response["deleted"], uri: uri, raw: response }
      rescue LLMAPIError, Error
        raise
      rescue => e
        raise LLMAPIError, "Failed to delete SiliconFlow voice: #{e.message}"
      end
    end
  end
end
