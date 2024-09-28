require 'erb'

module SmartPrompt
  class PromptTemplate
    def initialize(template_file)
      @template_file = template_file
      @template = File.read(template_file)
    end

    def render(params = {})
      ERB.new(@template, trim_mode: '-').result(binding_with_params(params))
    end

    def reload
      @template = File.read(@template_file)
    end

    private

    def binding_with_params(params)
      params_binding = binding
      params.each do |key, value|
        params_binding.local_variable_set(key, value)
      end
      params_binding
    end

    class << self
      def load_templates(template_dir)
        templates = {}
        Dir.glob(File.join(template_dir, '*.erb')).each do |file|
          name = File.basename(file, '.erb')
          templates[name] = new(file)
        end
        templates
      end

      def create(name, content)
        File.write(File.join(template_dir, "#{name}.erb"), content)
        new(File.join(template_dir, "#{name}.erb"))
      end

      def template_dir
        @template_dir ||= 'templates'
      end

      def template_dir=(dir)
        @template_dir = dir
      end
    end
  end
end