require "base64"
require "net/http"
require "uri"

module SmartPrompt
  # Shared multimodal-message normalization for Net::HTTP adapters (ZhipuAI, SenseNova,
  # SiliconFlow). Turns an OpenAI-style content array into the shape the provider expects,
  # inlining local image/audio/video files as base64 data URLs and passing http(s)/data
  # URLs through. Each adapter previously carried a near-identical copy of this logic.
  #
  # SiliconFlow's variant is the superset (image_url + video_url + audio_url, preserving
  # detail/max_frames/fps); Zhipu/SenseNova only ever send image_url, which is a subset.
  module MultimodalMessages
    SUPPORTED_IMAGE_FORMATS = %w[jpg jpeg png gif bmp webp].freeze

    def process_multimodal_messages(messages)
      messages.map do |msg|
        role = msg[:role] || msg["role"]
        content = msg[:content] || msg["content"]
        content = content.map { |item| normalize_content_item(item) } if content.is_a?(Array)
        { "role" => role, "content" => content }
      end
    end

    def normalize_content_item(item)
      return { "type" => "text", "text" => item.to_s } unless item.is_a?(Hash)

      case item[:type] || item["type"]
      when "image_url"
        normalize_media_part(item, "image_url", :image)
      when "video_url"
        normalize_media_part(item, "video_url", :video)
      when "audio_url"
        normalize_media_part(item, "audio_url", :audio)
      else
        stringify_hash(item)
      end
    end

    # Build an image_url/video_url/audio_url part, inlining local files as data URLs and
    # preserving any extra keys (detail, max_frames, fps) on the media hash.
    def normalize_media_part(item, type, media_kind)
      iu = item[type.to_sym] || item[type]
      if iu.is_a?(Hash)
        url = iu[:url] || iu["url"]
        part = { "type" => type, type => { "url" => normalize_media_url(url, media_kind) } }
        iu.each { |k, v| part[type][k.to_s] = stringify_hash(v) unless k.to_s == "url" }
        part
      else
        { "type" => type, type => { "url" => normalize_media_url(iu, media_kind) } }
      end
    end

    # Resolve a media URL embedded in a message: http(s)/data pass through; a local path
    # is base64-encoded as a data URL.
    def normalize_media_url(url, kind = :image)
      return url if url.nil?
      return url if url.start_with?("http://", "https://", "data:")

      label = kind == :image ? "Image" : kind.to_s.capitalize
      raise Error, "#{label} file not found: #{url}" unless File.exist?(url)
      ext = File.extname(url).downcase.delete(".")
      case kind
      when :image
        raise Error, "Unsupported image format: #{ext}" unless SUPPORTED_IMAGE_FORMATS.include?(ext)
        mime = ext == "jpg" ? "jpeg" : ext
        "data:image/#{mime};base64,#{Base64.strict_encode64(File.binread(url))}"
      when :audio
        "data:audio/#{ext.empty? ? 'wav' : ext};base64,#{Base64.strict_encode64(File.binread(url))}"
      when :video
        "data:video/#{ext.empty? ? 'mp4' : ext};base64,#{Base64.strict_encode64(File.binread(url))}"
      end
    end

    # Single-arg image-only shim (call sites like generate_video pass a plain image URL).
    def normalize_image_url(url)
      normalize_media_url(url, :image)
    end

    # Accept a local path, a base64 data URL, or an http(s) URL for image-edit /
    # image-to-video `image` fields.
    def normalize_input_image(image)
      return image if image.nil?

      if image.is_a?(String)
        return image if image.start_with?("data:")
        return image if image.start_with?("http://", "https://")
      end

      raise Error, "Image file not found: #{image}" unless File.exist?(image)
      ext = File.extname(image).downcase.delete(".")
      raise Error, "Unsupported image format: #{ext}" unless SUPPORTED_IMAGE_FORMATS.include?(ext)
      mime = ext == "jpg" ? "jpeg" : ext
      "data:image/#{mime};base64,#{Base64.strict_encode64(File.binread(image))}"
    end

    def stringify_hash(hash)
      case hash
      when Hash
        hash.each_with_object({}) { |(k, v), memo| memo[k.to_s] = stringify_hash(v) }
      when Array
        hash.map { |v| stringify_hash(v) }
      else
        hash
      end
    end
  end
end
