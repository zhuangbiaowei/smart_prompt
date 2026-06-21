# TTS Workers for SmartPrompt
# These workers demonstrate the new text-to-speech capabilities

# Basic text-to-speech worker
SmartPrompt.define_worker :tts_synthesizer do
  use "tts_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  # Prepare parameters for TTS synthesis
  tts_params = {
    text: params[:text],
    voice: params[:voice] || "alloy",
    speed: params[:speed] || 1.0,
    response_format: params[:response_format] || "mp3",
    language: params[:language]
  }

  # Call the TTS adapter directly
  adapter = engine.llms["tts_service"]

  if params[:save_to_file]
    # Synthesize and save to file
    output_dir = params[:output_dir] || "./generated_audio"
    filename_prefix = params[:filename_prefix] || "tts_audio"
    output_path = File.join(output_dir, "#{filename_prefix}_#{Time.now.to_i}.#{tts_params[:response_format]}")

    result = adapter.synthesize_to_file(
      tts_params[:text],
      output_path,
      voice: tts_params[:voice],
      model: params[:model],
      speed: tts_params[:speed],
      response_format: tts_params[:response_format],
      language: tts_params[:language]
    )

    { audio_file: result }
  else
    # Synthesize and return audio data
    audio_data = adapter.synthesize_speech(
      tts_params[:text],
      voice: tts_params[:voice],
      model: params[:model],
      speed: tts_params[:speed],
      response_format: tts_params[:response_format],
      language: tts_params[:language]
    )

    { audio_data: audio_data }
  end
end

# Multi-language TTS worker
SmartPrompt.define_worker :multilingual_tts do
  use "tts_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  # Prepare parameters for multilingual TTS
  tts_params = {
    text: params[:text],
    voice: params[:voice] || "alloy",
    speed: params[:speed] || 1.0,
    response_format: params[:response_format] || "mp3",
    language: params[:language]
  }

  # Auto-detect language if not specified
  unless tts_params[:language]
    # Simple language detection based on text content
    if params[:text] =~ /[\u4e00-\u9fff]/
      tts_params[:language] = "zh"
    elsif params[:text] =~ /[\u3040-\u309f\u30a0-\u30ff]/
      tts_params[:language] = "ja"
    elsif params[:text] =~ /[\uac00-\ud7af]/
      tts_params[:language] = "ko"
    else
      tts_params[:language] = "en"
    end
  end

  adapter = engine.llms["tts_service"]

  if params[:save_to_file]
    output_dir = params[:output_dir] || "./multilingual_audio"
    filename_prefix = params[:filename_prefix] || "multilingual_tts"
    output_path = File.join(output_dir, "#{filename_prefix}_#{tts_params[:language]}_#{Time.now.to_i}.#{tts_params[:response_format]}")

    result = adapter.synthesize_to_file(
      tts_params[:text],
      output_path,
      voice: tts_params[:voice],
      model: params[:model],
      speed: tts_params[:speed],
      response_format: tts_params[:response_format],
      language: tts_params[:language]
    )

    {
      audio_file: result,
      detected_language: tts_params[:language]
    }
  else
    audio_data = adapter.synthesize_speech(
      tts_params[:text],
      voice: tts_params[:voice],
      model: params[:model],
      speed: tts_params[:speed],
      response_format: tts_params[:response_format],
      language: tts_params[:language]
    )

    {
      audio_data: audio_data,
      detected_language: tts_params[:language]
    }
  end
end

# Voice selection worker
SmartPrompt.define_worker :voice_selector do
  use "tts_service"

  adapter = engine.llms["tts_service"]

  # Get available voices
  available_voices = adapter.available_voices

  # If voice parameter is provided, use it for synthesis
  if params[:text]
    tts_params = {
      text: params[:text],
      voice: params[:voice] || "alloy",
      speed: params[:speed] || 1.0,
      response_format: params[:response_format] || "mp3"
    }

    if params[:save_to_file]
      output_dir = params[:output_dir] || "./voice_samples"
      filename_prefix = params[:filename_prefix] || "voice_sample"
      output_path = File.join(output_dir, "#{filename_prefix}_#{tts_params[:voice]}_#{Time.now.to_i}.#{tts_params[:response_format]}")

      result = adapter.synthesize_to_file(
        tts_params[:text],
        output_path,
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format]
      )

      {
        available_voices: available_voices,
        selected_voice: tts_params[:voice],
        audio_file: result
      }
    else
      audio_data = adapter.synthesize_speech(
        tts_params[:text],
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format]
      )

      {
        available_voices: available_voices,
        selected_voice: tts_params[:voice],
        audio_data: audio_data
      }
    end
  else
    # Just return available voices
    { available_voices: available_voices }
  end
end

# Speed variation worker
SmartPrompt.define_worker :speed_variation_tts do
  use "tts_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  results = []

  # Generate audio at different speeds
  speeds = params[:speeds] || [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

  speeds.each do |speed|
    tts_params = {
      text: params[:text],
      voice: params[:voice] || "alloy",
      speed: speed,
      response_format: params[:response_format] || "mp3"
    }

    adapter = engine.llms["tts_service"]

    if params[:save_to_file]
      output_dir = params[:output_dir] || "./speed_variations"
      filename_prefix = params[:filename_prefix] || "speed_#{speed.to_s.gsub('.', '_')}"
      output_path = File.join(output_dir, "#{filename_prefix}_#{Time.now.to_i}.#{tts_params[:response_format]}")

      result = adapter.synthesize_to_file(
        tts_params[:text],
        output_path,
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format]
      )

      results << {
        speed: speed,
        audio_file: result
      }
    else
      audio_data = adapter.synthesize_speech(
        tts_params[:text],
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format]
      )

      results << {
        speed: speed,
        audio_data: audio_data
      }
    end
  end

  { speed_variations: results }
end

# Custom voice management worker
SmartPrompt.define_worker :custom_voice_manager do
  use "tts_service"

  adapter = engine.llms["tts_service"]

  case params[:action]
  when "list"
    # List custom voices
    custom_voices = adapter.list_custom_voices
    { action: "list", custom_voices: custom_voices }

  when "create"
    # Create custom voice
    if params[:reference_audio_file]
      voice_data = adapter.create_custom_voice(
        params[:name],
        params[:reference_audio_file],
        description: params[:description]
      )
      { action: "create", voice_data: voice_data }
    else
      { error: "reference_audio_file is required for creating custom voice" }
    end

  when "delete"
    # Delete custom voice
    if params[:voice_id]
      result = adapter.delete_custom_voice(params[:voice_id])
      { action: "delete", result: result }
    else
      { error: "voice_id is required for deleting custom voice" }
    end

  when "synthesize"
    # Synthesize using custom voice
    if params[:voice_id] && params[:text]
      tts_params = {
        text: params[:text],
        voice: params[:voice_id], # Use voice_id as custom voice
        speed: params[:speed] || 1.0,
        response_format: params[:response_format] || "mp3"
      }

      if params[:save_to_file]
        output_dir = params[:output_dir] || "./custom_voice_audio"
        filename_prefix = params[:filename_prefix] || "custom_voice"
        output_path = File.join(output_dir, "#{filename_prefix}_#{params[:voice_id]}_#{Time.now.to_i}.#{tts_params[:response_format]}")

        result = adapter.synthesize_to_file(
          tts_params[:text],
          output_path,
          voice: tts_params[:voice],
          model: params[:model],
          speed: tts_params[:speed],
          response_format: tts_params[:response_format]
        )

        {
          action: "synthesize",
          voice_id: params[:voice_id],
          audio_file: result
        }
      else
        audio_data = adapter.synthesize_speech(
          tts_params[:text],
          voice: tts_params[:voice],
          model: params[:model],
          speed: tts_params[:speed],
          response_format: tts_params[:response_format]
        )

        {
          action: "synthesize",
          voice_id: params[:voice_id],
          audio_data: audio_data
        }
      end
    else
      { error: "voice_id and text are required for synthesis" }
    end

  else
    # Default action: list voices
    predefined_voices = adapter.available_voices
    custom_voices = adapter.list_custom_voices
    {
      action: "default",
      predefined_voices: predefined_voices,
      custom_voices: custom_voices
    }
  end
end

# Batch TTS worker for multiple texts
SmartPrompt.define_worker :batch_tts do
  use "tts_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  results = []

  # Process multiple texts
  texts = params[:texts] || [params[:text]]

  texts.each_with_index do |text, index|
    tts_params = {
      text: text,
      voice: params[:voice] || "alloy",
      speed: params[:speed] || 1.0,
      response_format: params[:response_format] || "mp3",
      language: params[:language]
    }

    adapter = engine.llms["tts_service"]

    if params[:save_to_file]
      output_dir = params[:output_dir] || "./batch_audio"
      filename_prefix = params[:filename_prefix] || "batch_tts_#{index}"
      output_path = File.join(output_dir, "#{filename_prefix}_#{Time.now.to_i}.#{tts_params[:response_format]}")

      result = adapter.synthesize_to_file(
        tts_params[:text],
        output_path,
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format],
        language: tts_params[:language]
      )

      results << {
        text: text,
        index: index,
        audio_file: result
      }
    else
      audio_data = adapter.synthesize_speech(
        tts_params[:text],
        voice: tts_params[:voice],
        model: params[:model],
        speed: tts_params[:speed],
        response_format: tts_params[:response_format],
        language: tts_params[:language]
      )

      results << {
        text: text,
        index: index,
        audio_data: audio_data
      }
    end
  end

  { batch_results: results }
end