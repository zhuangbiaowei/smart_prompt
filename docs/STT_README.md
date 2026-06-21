# SmartPrompt STT Guide

This guide explains how to use the new Speech-to-Text (STT) capabilities in SmartPrompt.

## Overview

The STT feature adds support for:
- **Speech-to-Text Transcription**: Convert audio files to text
- **URL-based Transcription**: Transcribe audio from URLs
- **Multi-language Support**: Chinese, English, Japanese, Korean
- **Batch Processing**: Process multiple audio files efficiently
- **Language Detection**: Automatically detect language from audio
- **Multiple Formats**: JSON, text, SRT, VTT output formats

## Installation

Make sure you have the required dependencies:

```bash
gem install openai
```

## Configuration

Add the STT adapter to your configuration:

```yaml
# config.yml
adapters:
  multimodal: "MultimodalAdapter"
  image_generation: "ImageGenerationAdapter"
  video_generation: "VideoGenerationAdapter"
  tts: "TTSAdapter"
  stt: "STTAdapter"

llms:
  stt_service:
    adapter: "stt"
    url: "https://api.siliconflow.cn/v1/"
    api_key: "ENV[SILICONFLOW_API_KEY]"
    model: "FunAudioLLM/CosyVoice2-0.5B"

default_llm: "qwen_vl"
template_path: "./templates"
worker_path: "./workers"
logger_file: "./logs/smart_prompt.log"
```

## Available Workers

### 1. STT Transcriber Worker
Basic speech-to-text transcription.

```ruby
result = engine.call_worker(:stt_transcriber, {
  audio_file: "./audio.wav",
  language: "zh",              # Optional: "zh", "en", "ja", "ko"
  prompt: "专业术语",           # Optional: Context prompt
  temperature: 0.0,            # Optional: 0.0 to 1.0
  response_format: "json"      # Optional: "json", "text", "srt", "vtt"
})
```

### 2. STT URL Transcriber Worker
Transcribe audio from URL.

```ruby
result = engine.call_worker(:stt_url_transcriber, {
  audio_url: "https://example.com/audio.wav",
  language: "en",
  response_format: "text"
})
```

### 3. Batch STT Worker
Process multiple audio files.

```ruby
result = engine.call_worker(:batch_stt, {
  audio_files: [
    "./audio1.wav",
    "./audio2.mp3",
    "./audio3.webm"
  ],
  language: "zh",
  temperature: 0.0
})
```

### 4. Audio Info Worker
Get audio file information.

```ruby
result = engine.call_worker(:audio_info, {
  audio_file: "./audio.wav"
})
```

### 5. Language Detector Worker
Detect language from audio or text.

```ruby
# From audio file
result = engine.call_worker(:language_detector, {
  audio_file: "./audio.wav"
})

# From text
result = engine.call_worker(:language_detector, {
  text: "这是一个中文文本"
})
```

### 6. Multi-language STT Worker
Automatic language detection and transcription.

```ruby
result = engine.call_worker(:multilingual_stt, {
  audio_file: "./audio.wav"
})
```

### 7. STT Format Converter Worker
Generate transcriptions in multiple formats.

```ruby
result = engine.call_worker(:stt_format_converter, {
  audio_file: "./audio.wav",
  formats: ["json", "text", "srt", "vtt"]
})
```

## Direct Adapter Usage

You can also use the adapter directly without workers:

```ruby
# Get the adapter
adapter = engine.llms["stt_service"]

# Transcribe audio file
transcription_data = adapter.transcribe_audio(
  "./audio.wav",
  language: "zh",
  temperature: 0.0,
  response_format: "json"
)

# Transcribe from URL
transcription_data = adapter.transcribe_audio_url(
  "https://example.com/audio.wav",
  language: "en",
  response_format: "text"
)

# Batch transcription
batch_result = adapter.transcribe_batch(
  ["./audio1.wav", "./audio2.mp3"],
  language: "zh"
)

# Get audio information
audio_info = adapter.get_audio_info("./audio.wav")

# Detect language
detected_language = adapter.detect_language("这是一个中文文本")
```

## Response Formats

### Transcription Response
```ruby
{
  text: "转录的文本内容",           # Transcribed text
  language: "zh",                  # Language used
  duration: 120,                   # Audio duration in seconds
  file_size: 1024000,              # File size in bytes
  format: "wav"                    # Audio format
}
```

### Batch Response
```ruby
{
  total_files: 3,                  # Total files processed
  successful: 2,                   # Successful transcriptions
  failed: 1,                       # Failed transcriptions
  results: [                       # Individual results
    {
      file: "./audio1.wav",
      index: 0,
      transcription: { ... },
      success: true
    },
    {
      file: "./audio2.wav",
      index: 1,
      error: "File not found",
      success: false
    }
  ]
}
```

### Audio Information Response
```ruby
{
  file_path: "./audio.wav",        # File path
  file_name: "audio.wav",          # File name
  file_size: 1024000,              # File size in bytes
  format: "wav",                   # Audio format
  estimated_duration: 120,         # Estimated duration in seconds
  supported: true                  # Whether format is supported
}
```

## Supported Models

SiliconFlow supports various STT models:
- `FunAudioLLM/CosyVoice2-0.5B` - Multi-language speech recognition
- `fnlp/MOSS-TTSD-v0.5` - High accuracy speech recognition

## Supported Audio Formats

- `mp3` - MP3 format
- `mp4` - MP4 format
- `mpeg` - MPEG format
- `mpga` - MPGA format
- `m4a` - M4A format
- `wav` - WAV format
- `webm` - WebM format

## Language Support

- `zh` - Chinese
- `en` - English
- `ja` - Japanese
- `ko` - Korean

## Response Formats

- `json` - JSON format (default)
- `text` - Plain text format
- `srt` - SubRip subtitle format
- `vtt` - WebVTT subtitle format

## File Size Limits

- **Maximum file size**: 25MB
- **Recommended duration**: Under 30 minutes
- **Bitrate**: Standard audio bitrates

## Error Handling

```ruby
begin
  result = engine.call_worker(:stt_transcriber, params)
rescue SmartPrompt::LLMAPIError => e
  puts "API Error: #{e.message}"
rescue SmartPrompt::Error => e
  puts "General Error: #{e.message}"
rescue => e
  puts "Unexpected Error: #{e.message}"
end
```

## Best Practices

1. **Audio Quality**: Use clear audio with minimal background noise
2. **Language Specification**: Specify language for better accuracy
3. **File Size**: Keep files under 25MB for optimal performance
4. **Batch Processing**: Use batch workers for multiple files
5. **Format Selection**: Choose appropriate response format for your use case
6. **Temperature**: Use lower temperature (0.0-0.2) for more accurate transcriptions

## Example

See `examples/stt_example.rb` for complete working examples.

## Troubleshooting

**Common Issues:**
- **API Key Error**: Ensure `SILICONFLOW_API_KEY` environment variable is set
- **File Not Found**: Check file path and permissions
- **Unsupported Format**: Use only supported audio formats
- **File Too Large**: Maximum file size is 25MB
- **Network Error**: Check internet connection and API endpoint

**Error Messages:**
- `Audio file not found` - Check file path
- `Unsupported audio format` - Use supported formats only
- `Audio file too large` - Reduce file size to under 25MB
- `Unsupported response format` - Use only supported response formats
- `Network error: Unable to connect to STT API` - Check network connectivity

## Performance Tips

1. **Preprocessing**: Normalize audio levels before transcription
2. **Language Detection**: Use automatic detection for mixed-language content
3. **Batch Processing**: Process multiple files together for efficiency
4. **Format Selection**: Use JSON for structured data, text for simple output
5. **Error Recovery**: Implement retry logic for network failures