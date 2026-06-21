# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.5.1] - 2026-06-21
### Added
- **SenseNova (商汤日日新) support** — unified `SenseNovaAdapter` covering chat (商量), multimodal vision, Cupido embeddings, and 秒画 text-to-image, with SSE streaming and reasoning-field handling
- **智谱 AI (BigModel / GLM) support** — unified `ZhipuAIAdapter` covering all REST categories: chat (GLM-4), vision (GLM-4V), embeddings (embedding-3), text-to-image (CogView), text-to-video (CogVideoX async), TTS (GLM-TTS), ASR (GLM-ASR), and rerank
- Media adapters: multimodal, image generation, video generation, TTS, STT
- Intelligent conversation history management (sliding-window, relevance-based, summary-based, hybrid strategies) with session isolation, compression, persistence, and LRU caching
- Token counter, message/session models, and persistence layer
- Example configs, workers, and self-contained examples for every provider
- Integrated upstream gemma4 multimodal support (`use_model`, `thinking`, `image`/`audio`/`video`, `multimodal_prompt`) and `request_options` plumbing

### Fixed
- Expose `engine` on `WorkerContext` so workers can reach a configured adapter directly (fixes the `engine.llms[...]` pattern used by media workers)
- `Worker#execute` default session_id was hard-coded to `"default"`, leaving the per-worker session branch as dead code and collapsing all history-using workers onto one shared session; now generates `worker_<name>_<ts>`
- `AnthropicAdapter`: add `extract_content_from_response` and stop double-wrapping multimodal (array) content
- file_upload multimodal fix: base64-encode local image/audio/video files instead of passing raw paths

## [0.4.1] - 2026-04-22
### Fixed
- Re-release package with `lib/smart_prompt/anthropic_adapter.rb`, which is required by the gem entrypoint.

## [0.4.0] - 2026-04-22
### Added
- Anthropic adapter support.

## [0.3.6] - 2026-04-08
### Changed
- Bumped `ruby-openai` dependency from `8.1.0` to `8.3.0`

## [0.3.2] - 2025-05-18
### Added
- Initial CHANGELOG.md file
### Fixed
- Comprehensive message logs
- Fix gemspec's bug

## [0.2.4] - 2025-04-06
### Fixed
- Message history bug fix
- General updates and improvements

## [0.2.3] - 2025-04-06
### Added
- Support for automatic conversation history recording in multi-turn dialogues

## [0.1.6] - 2024-10-18
### Added
- Custom error classes
- Logger configuration
### Changed
- Updated README
- General improvements

## [0.1.0] - 2024-09-18
### Added
- Initial gem release
- Llama.cpp adapter
- Basic configuration parameters
- Environment bug fixes
