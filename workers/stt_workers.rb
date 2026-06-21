# STT Workers for SmartPrompt
# These workers demonstrate the new speech-to-text capabilities

# Basic speech-to-text worker
SmartPrompt.define_worker :stt_transcriber do
  use "stt_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  # Prepare parameters for STT transcription
  stt_params = {
    audio_file: params[:audio_file],
    language: params[:language],
    prompt: params[:prompt],
    temperature: params[:temperature] || 0.0,
    response_format: params[:response_format] || "json"
  }

  # Call the STT adapter directly
  adapter = engine.llms["stt_service"]

  # Transcribe audio
  transcription_data = adapter.transcribe_audio(
    stt_params[:audio_file],
    model: params[:model],
    language: stt_params[:language],
    prompt: stt_params[:prompt],
    temperature: stt_params[:temperature],
    response_format: stt_params[:response_format]
  )

  { transcription: transcription_data }
end

# URL-based speech-to-text worker
SmartPrompt.define_worker :stt_url_transcriber do
  use "stt_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  # Prepare parameters for URL-based STT
  stt_params = {
    audio_url: params[:audio_url],
    language: params[:language],
    prompt: params[:prompt],
    temperature: params[:temperature] || 0.0,
    response_format: params[:response_format] || "json"
  }

  adapter = engine.llms["stt_service"]

  # Transcribe audio from URL
  transcription_data = adapter.transcribe_audio_url(
    stt_params[:audio_url],
    model: params[:model],
    language: stt_params[:language],
    prompt: stt_params[:prompt],
    temperature: stt_params[:temperature],
    response_format: stt_params[:response_format]
  )

  { transcription: transcription_data }
end

# Batch speech-to-text worker
SmartPrompt.define_worker :batch_stt do
  use "stt_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  # Process multiple audio files
  audio_files = params[:audio_files] || [params[:audio_file]]

  adapter = engine.llms["stt_service"]

  # Batch transcribe audio files
  batch_result = adapter.transcribe_batch(
    audio_files,
    model: params[:model],
    language: params[:language],
    prompt: params[:prompt],
    temperature: params[:temperature] || 0.0
  )

  { batch_result: batch_result }
end

# Audio file information worker
SmartPrompt.define_worker :audio_info do
  use "stt_service"

  adapter = engine.llms["stt_service"]

  # Get audio file information
  audio_info = adapter.get_audio_info(params[:audio_file])

  { audio_info: audio_info }
end

# Language detection worker
SmartPrompt.define_worker :language_detector do
  use "stt_service"

  adapter = engine.llms["stt_service"]

  if params[:audio_file]
    # Transcribe and detect language
    transcription_data = adapter.transcribe_audio(
      params[:audio_file],
      model: params[:model],
      language: params[:language],
      temperature: params[:temperature] || 0.0
    )

    # Detect language from transcribed text
    detected_language = adapter.detect_language(transcription_data[:text])

    {
      transcription: transcription_data,
      detected_language: detected_language
    }
  elsif params[:text]
    # Detect language from text directly
    detected_language = adapter.detect_language(params[:text])

    {
      text: params[:text],
      detected_language: detected_language
    }
  else
    { error: "Either audio_file or text parameter is required" }
  end
end

# Multi-language STT worker
SmartPrompt.define_worker :multilingual_stt do
  use "stt_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  adapter = engine.llms["stt_service"]

  # First transcribe without language specification
  transcription_data = adapter.transcribe_audio(
    params[:audio_file],
    model: params[:model],
    temperature: params[:temperature] || 0.0
  )

  # Detect language from transcribed text
  detected_language = adapter.detect_language(transcription_data[:text])

  # Re-transcribe with detected language for better accuracy
  if detected_language && detected_language != "en"
    improved_transcription = adapter.transcribe_audio(
      params[:audio_file],
      model: params[:model],
      language: detected_language,
      temperature: params[:temperature] || 0.0
    )

    {
      initial_transcription: transcription_data,
      improved_transcription: improved_transcription,
      detected_language: detected_language
    }
  else
    {
      transcription: transcription_data,
      detected_language: detected_language
    }
  end
end

# Format conversion worker
SmartPrompt.define_worker :stt_format_converter do
  use "stt_service"
  model "FunAudioLLM/CosyVoice2-0.5B"

  adapter = engine.llms["stt_service"]

  # Generate transcriptions in different formats
  formats = params[:formats] || %w[json text srt vtt]
  results = {}

  formats.each do |format|
    transcription_data = adapter.transcribe_audio(
      params[:audio_file],
      model: params[:model],
      language: params[:language],
      temperature: params[:temperature] || 0.0,
      response_format: format
    )

    results[format] = transcription_data
  end

  { format_results: results }
end