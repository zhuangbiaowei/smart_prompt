# SmartPrompt TTS Guide

This guide explains how to use the new Text-to-Speech (TTS) capabilities in SmartPrompt.

## Overview

The TTS feature adds support for:
- **Text-to-Speech Synthesis**: Convert text to natural-sounding speech
- **Multi-language Support**: Chinese, English, Japanese, Korean
- **Voice Selection**: Multiple predefined voices and custom voices
- **Speed Control**: Adjust speech speed from 0.25x to 4.0x
- **Multiple Formats**: MP3, WAV, Opus, PCM output formats
- **Custom Voices**: Create and manage custom voices from reference audio

## Installation

Make sure you have the required dependencies:

```bash
gem install openai
```

## Configuration

Add the TTS adapter to your configuration:

```yaml
# config.yml
adapters:
  multimodal: "MultimodalAdapter"
  image_generation: "ImageGenerationAdapter"
  video_generation: "VideoGenerationAdapter"
  tts: "TTSAdapter"

llms:
  tts_service:
    adapter: "tts"
    url: "https://api.siliconflow.cn/v1/"
    api_key: "ENV[SILICONFLOW_API_KEY]"
    model: "FunAudioLLM/CosyVoice2-0.5B"

default_llm: "tts_service"
template_path: "./templates"
worker_path: "./workers"
logger_file: "./logs/smart_prompt.log"
```

## Available Workers

### 1. TTS Synthesizer Worker
Basic text-to-speech synthesis.

```ruby
result = engine.call_worker(:tts_synthesizer, {
  text: "欢迎使用智能提示系统",
  voice: "alloy",              # Optional: "alloy", "echo", "fable", "onyx", "nova", "shimmer"
  speed: 1.0,                  # Optional: 0.25 to 4.0
  response_format: "mp3",      # Optional: "mp3", "wav", "opus", "pcm"
  language: "zh",              # Optional: "zh", "en", "ja", "ko"
  save_to_file: true,          # Optional: Save audio to file
  output_dir: "./audio",       # Optional: Output directory
  filename_prefix: "tts"       # Optional: Filename prefix
})
```

### 2. Multilingual TTS Worker
Automatic language detection and synthesis.

```ruby
result = engine.call_worker(:multilingual_tts, {
  text: "Hello, this is a demonstration",
  voice: "echo",
  save_to_file: true
})
```

### 3. Voice Selector Worker
List available voices and test different voices.

```ruby
result = engine.call_worker(:voice_selector, {
  text: "测试不同音色的效果",
  voice: "nova",
  save_to_file: true
})
```

### 4. Speed Variation Worker
Generate audio at different speeds.

```ruby
result = engine.call_worker(:speed_variation_tts, {
  text: "这是一个语速变化的演示",
  speeds: [0.5, 0.75, 1.0, 1.5, 2.0],
  save_to_file: true
})
```

### 5. Custom Voice Manager Worker
Manage custom voices (create, list, delete, synthesize).

```ruby
# List voices
result = engine.call_worker(:custom_voice_manager, {
  action: "list"
})

# Create custom voice
result = engine.call_worker(:custom_voice_manager, {
  action: "create",
  name: "my_voice",
  reference_audio_file: "./reference.wav",
  description: "My custom voice"
})

# Delete custom voice
result = engine.call_worker(:custom_voice_manager, {
  action: "delete",
  voice_id: "voice_123"
})

# Synthesize with custom voice
result = engine.call_worker(:custom_voice_manager, {
  action: "synthesize",
  voice_id: "voice_123",
  text: "使用自定义音色朗读",
  save_to_file: true
})
```

### 6. Batch TTS Worker
Process multiple texts in batch.

```ruby
result = engine.call_worker(:batch_tts, {
  texts: [
    "第一条文本",
    "第二条文本",
    "第三条文本"
  ],
  voice: "alloy",
  save_to_file: true
})
```

## Direct Adapter Usage

You can also use the adapter directly without workers:

```ruby
# Get the adapter
adapter = engine.llms["tts_service"]

# Synthesize speech
audio_data = adapter.synthesize_speech(
  "这是一个直接合成的演示",
  voice: "echo",
  speed: 1.2,
  response_format: "mp3"
)

# Synthesize and save to file
result = adapter.synthesize_to_file(
  "保存到文件的演示",
  "./audio/demo.mp3",
  voice: "nova",
  speed: 1.0
)

# Get available voices
voices = adapter.available_voices

# Create custom voice
voice_data = adapter.create_custom_voice(
  "my_voice",
  "./reference.wav",
  description: "My custom voice"
)

# List custom voices
custom_voices = adapter.list_custom_voices

# Delete custom voice
result = adapter.delete_custom_voice("voice_123")
```

## Response Formats

### Audio Data Response
```ruby
{
  audio_data: "data:audio/mp3;base64,...",  # Base64 encoded audio
  format: "mp3",                           # Audio format
  text_length: 25,                         # Input text length
  voice: "alloy"                           # Voice used
}
```

### File Response
```ruby
{
  file_path: "./audio/demo.mp3",           # Saved file path
  text_length: 25,                         # Input text length
  voice: "alloy",                          # Voice used
  format: "mp3"                            # Audio format
}
```

### Voice Management Response
```ruby
{
  voice_id: "voice_123",                   # Voice identifier
  name: "my_voice",                        # Voice name
  status: "active",                        # Voice status
  created_at: "2024-01-01..."              # Creation timestamp
}
```

## Supported Models

SiliconFlow supports various TTS models:
- `FunAudioLLM/CosyVoice2-0.5B` - Multi-language support with emotion control
- `fnlp/MOSS-TTSD-v0.5` - High expressiveness, dual voice cloning

## Predefined Voices

- `alloy` - 沉稳男声alex
- `echo` - 温柔女声claire
- `fable` - 活泼女声fable
- `onyx` - 磁性男声onyx
- `nova` - 甜美女声nova
- `shimmer` - 优雅女声shimmer

## Language Support

- `zh` - Chinese
- `en` - English
- `ja` - Japanese
- `ko` - Korean

## Audio Formats

- `mp3` - MP3 format (default)
- `wav` - WAV format
- `opus` - Opus format
- `pcm` - PCM format

## Speed Control

- **Range**: 0.25 to 4.0
- **Default**: 1.0 (normal speed)
- **Slow**: 0.25 - 0.75
- **Fast**: 1.25 - 4.0

## Custom Voice Requirements

- **Reference Audio**: 8-10 seconds recommended
- **Audio Quality**: Clear speech, no background noise
- **File Size**: Maximum 5MB
- **Formats**: Common audio formats supported

## Error Handling

```ruby
begin
  result = engine.call_worker(:tts_synthesizer, params)
rescue SmartPrompt::LLMAPIError => e
  puts "API Error: #{e.message}"
rescue SmartPrompt::Error => e
  puts "General Error: #{e.message}"
rescue => e
  puts "Unexpected Error: #{e.message}"
end
```

## Best Practices

1. **Text Preparation**: Remove unnecessary spaces, use proper punctuation
2. **Language Selection**: Specify language for better pronunciation
3. **Speed Adjustment**: Use 0.8-1.2 for natural speech
4. **Voice Selection**: Test different voices for your use case
5. **Batch Processing**: Use batch workers for multiple texts
6. **File Management**: Use `save_to_file: true` for persistent storage

## Example

See `examples/tts_example.rb` for complete working examples.

## Troubleshooting

**Common Issues:**
- **API Key Error**: Ensure `SILICONFLOW_API_KEY` environment variable is set
- **Text Too Long**: Maximum 4096 characters per request
- **Invalid Voice**: Use only predefined voice names or valid custom voice IDs
- **Speed Out of Range**: Speed must be between 0.25 and 4.0
- **File Permissions**: Ensure write permissions for output directories
- **Reference Audio**: For custom voices, use clear 8-10 second audio files

**Error Messages:**
- `Text cannot be empty` - Provide non-empty text
- `Text too long` - Reduce text length to under 4096 characters
- `Unsupported response format` - Use only supported audio formats
- `Reference audio file not found` - Check file path for custom voice creation