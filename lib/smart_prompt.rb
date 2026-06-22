require File.expand_path('../smart_prompt/version', __FILE__)
require File.expand_path('../smart_prompt/token_counter', __FILE__)
require File.expand_path('../smart_prompt/message', __FILE__)
require File.expand_path('../smart_prompt/session', __FILE__)
require File.expand_path('../smart_prompt/context_strategy', __FILE__)
require File.expand_path('../smart_prompt/sliding_window_strategy', __FILE__)
require File.expand_path('../smart_prompt/relevance_based_strategy', __FILE__)
require File.expand_path('../smart_prompt/compression_engine', __FILE__)
require File.expand_path('../smart_prompt/summary_based_strategy', __FILE__)
require File.expand_path('../smart_prompt/hybrid_strategy', __FILE__)
require File.expand_path('../smart_prompt/persistence_layer', __FILE__)
require File.expand_path('../smart_prompt/lru_cache', __FILE__)
require File.expand_path('../smart_prompt/history_manager', __FILE__)
require File.expand_path('../smart_prompt/engine', __FILE__)
require File.expand_path('../smart_prompt/api_handler', __FILE__)
require File.expand_path('../smart_prompt/conversation', __FILE__)
require File.expand_path('../smart_prompt/llm_adapter', __FILE__)
require File.expand_path('../smart_prompt/openai_adapter', __FILE__)
require File.expand_path('../smart_prompt/anthropic_adapter', __FILE__)
require File.expand_path('../smart_prompt/llamacpp_adapter', __FILE__)
require File.expand_path('../smart_prompt/anthropic_adapter', __FILE__)
require File.expand_path('../smart_prompt/sensenova_adapter', __FILE__)
require File.expand_path('../smart_prompt/zhipu_adapter', __FILE__)
require File.expand_path('../smart_prompt/siliconflow_adapter', __FILE__)
require File.expand_path('../smart_prompt/multimodal_adapter', __FILE__)
require File.expand_path('../smart_prompt/image_generation_adapter', __FILE__)
require File.expand_path('../smart_prompt/video_generation_adapter', __FILE__)
require File.expand_path('../smart_prompt/tts_adapter', __FILE__)
require File.expand_path('../smart_prompt/stt_adapter', __FILE__)
require File.expand_path('../smart_prompt/prompt_template', __FILE__)
require File.expand_path('../smart_prompt/worker', __FILE__)

module SmartPrompt
  class Error < StandardError; end
  class ConfigurationError < Error; end
  class LLMAPIError < Error; end
  class CallWorkerError < Error; end
  class HistoryManagerError < Error; end

  attr_writer :logger

  def self.define_worker(name, &block)
    Worker.define(name, &block)
  end

  def self.run_worker(name, config_file, params = {})
    worker = Worker.new(name, config_file)
    worker.execute(params)
  end

  def self.logger=(logger)
    @logger = logger
  end
  
  def self.logger
    @logger ||= Logger.new($stdout).tap do |log|
      log.progname = self.name
    end
  end
end
