# frozen_string_literal: true

require_relative "lib/smart_prompt/version"

Gem::Specification.new do |spec|
  spec.name = "smart_prompt"
  spec.version = SmartPrompt::VERSION
  spec.authors = ["zhuang biaowei"]
  spec.email = ["zbw@kaiyuanshe.org"]

  spec.summary       = %q{A smart prompt management and LLM interaction gem}
  spec.description   = %q{SmartPrompt provides a flexible DSL for managing prompts, interacting with multiple LLMs, and creating composable task workers.}
  spec.homepage = "https://github.com/zhuangbiaowei/smart_prompt"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.0.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = "https://github.com/zhuangbiaowei/smart_prompt"
  spec.metadata["changelog_uri"] = "https://github.com/zhuangbiaowei/smart_prompt/blob/master/CHANGELOG.md"

  # Specify which files should be added to the gem when it is released.
  # The `git ls-files -z` loads the files in the RubyGem that have been added into git.
  gemspec = File.basename(__FILE__)
  spec.files = IO.popen(%w[git ls-files -z], chdir: __dir__, err: IO::NULL) do |ls|
    ls.readlines("\x0", chomp: true).reject do |f|
      (f == gemspec) ||
        f.start_with?(*%w[bin/ test/ spec/ features/ .git .github appveyor Gemfile])
    end
  end
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]

  # Uncomment to register a new dependency of your gem
  # spec.add_dependency "example-gem", "~> 1.0"
  spec.add_dependency "yaml", "~> 0.3.0"
  spec.add_dependency "ruby-openai", "~> 7.1.0"
  spec.add_dependency "ollama-ai", "~> 1.3.0"
  spec.add_dependency "json", "~> 2.7.1"
  spec.add_dependency "safe_ruby", "~> 1.0.4"

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
