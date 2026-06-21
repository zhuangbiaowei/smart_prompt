# 待删除文件列表

## 高优先级删除（安全且推荐）

### 构建产物
```bash
smart_prompt-0.3.4.gem
```

### 生成的媒体文件（占用空间较大）
```bash
generated_images/sunset_1.png
art_images/fantasy_forest_1.png
direct_images/cartoon_cat_1.png
direct_images/cartoon_cat_2.png
product_images/smartphone_1.png
```

### 日志文件
```bash
logs/smart_prompt.log
```

---

## 中优先级删除（开发辅助文件）

### 开发工具缓存和配置
```bash
.ruby-lsp/
.claude/settings.local.json
.vscode/launch.json
.kiro/
```

### 重复的文档文件（主文档已涵盖相关内容）
```bash
ANTHROPIC_EXAMPLES.md
IMAGE_GENERATION_README.md
TTS_README.md
STT_README.md
VIDEO_GENERATION_README.md
MULTIMODAL_README.md
QUICK_START_ANTHROPIC.md
HISTORY_MIGRATION_GUIDE.md
```

### 实现总结文档
```bash
examples/IMPLEMENTATION_SUMMARY.md
```

---

## 低优先级删除（示例和工作进程文件）

### 非核心示例文件（examples目录）
```bash
examples/anthropic_vision_example.rb
examples/anthropic_example.rb
examples/anthropic_tools_example.rb
examples/automatic_cleanup_example.rb
examples/chat_example.rb
examples/examples.rb
examples/fast_example.rb
examples/inner_thoughts_example.rb
examples/logging_example.rb
examples/message_example.rb
examples/monitoring_example.rb
examples/multimodal_example.rb
examples/structured_data_example.rb
```

### 非核心工作进程文件（workers目录）
```bash
workers/image_generation_workers.rb
workers/multimodal_workers.rb
workers/stt_workers.rb
workers/tts_workers.rb
workers/video_generation_workers.rb
```

---

## 其他可考虑删除的文档（可选）

### 实施细节文档（如果不再需要）
```bash
HISTORY_MANAGEMENT_GUIDE.md
MONITORING_GUIDE.md
RELEVANCE_BASED_STRATEGY_IMPLEMENTATION.md
```

---

## 总计

- **文件数量**: 41个文件/目录
- **预计释放空间**: 3.5MB - 4.5MB（主要为媒体文件和日志）

---

## 删除方法

可以使用以下命令批量删除：

```bash
# 删除生成的媒体文件和构建产物
rm -f smart_prompt-0.3.4.gem generated_images/sunset_1.png art_images/fantasy_forest_1.png direct_images/cartoon_cat_*.png product_images/smartphone_1.png logs/smart_prompt.log

# 删除示例文件（如果需要）
rm -f examples/*_example.rb examples/example.rb examples/examples.rb

# 删除工作进程文件（如果需要）
rm -f workers/*_workers.rb

# 删除docs文件（如果需要）
rm -f IMAGE_GENERATION_README.md TTS_README.md STT_README.md VIDEO_GENERATION_README.md MULTIMODAL_README.md ANTHROPIC_EXAMPLES.md QUICK_START_ANTHROPIC.md HISTORY_MIGRATION_GUIDE.md examples/IMPLEMENTATION_SUMMARY.md

# 删除开发工具配置文件（如果需要）
rm -rf .ruby-lsp/ .claude/ .vscode/ .kiro/
```

**注意**: 在删除任何文件之前，建议先进行备份或确认这些文件确实不再需要。
