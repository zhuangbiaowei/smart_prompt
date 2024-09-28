require File.expand_path('../smart_prompt/version', __FILE__)
require File.expand_path('../smart_prompt/engine', __FILE__)
require File.expand_path('../smart_prompt/conversation', __FILE__)
require File.expand_path('../smart_prompt/llm_adapter', __FILE__)
require File.expand_path('../smart_prompt/prompt_template', __FILE__)
require File.expand_path('../smart_prompt/worker', __FILE__)

module SmartPrompt
  class Error < StandardError; end

  def self.define_worker(name, &block)
    Worker.define(name, &block)
  end

  def self.run_worker(name, config_file, params = {})
    worker = Worker.new(name, config_file)
    worker.execute(params)
  end
end