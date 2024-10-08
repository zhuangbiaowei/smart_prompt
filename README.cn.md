# SmartPrompt

SmartPrompt 是一个强大的 Ruby gem，提供了一种领域特定语言（DSL），使其他 Ruby 程序能够更加方便、自然地调用各种大型语言模型（LLM）的能力。

## 主要特性

- 灵活的任务组合：以特定服务提供商 + 特定 LLM + 特定 prompt 的方式组合各种任务
- 子任务嵌套：支持以 DSL 形式组合调用其他子任务
- 性能优化：在保证质量的同时，提供性能最优或成本最低的解决方案

## 安装

将 gem 安装并添加到应用程序的 Gemfile 中，执行以下命令：

```
$ bundle add smart_prompt
```

如果不使用 bundler 来管理依赖，可以通过执行以下命令来安装 gem：

```
$ gem install smart_prompt
```

## 用法

更多示例请看项目 [SmartPromptDemo](https://github.com/zhuangbiaowei/SmartPromptDemo)