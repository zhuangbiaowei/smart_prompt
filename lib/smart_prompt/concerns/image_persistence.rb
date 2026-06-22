require "base64"
require "net/http"
require "uri"
require "fileutils"

module SmartPrompt
  # Shared image-saving logic for adapters that produce generated images (ZhipuAI,
  # SenseNova, SiliconFlow). Each previously carried a byte-identical copy of
  # save_image / save_single_image; this concern is the single source.
  #
  # Adapters override two hooks:
  #   * default_image_prefix — filename prefix when the caller passes none
  #     (e.g. "zhipu_image", "sensenova_image", "siliconflow_image")
  #   * provider_label       — human label for the "Saved N <label> image(s)" log line
  module ImagePersistence
    # Save one or many generated images to disk. Accepts the Array returned by
    # generate_image/edit_image or a single image hash. Returns the written paths.
    def save_image(image_data, output_dir = "./output", filename_prefix = nil)
      FileUtils.mkdir_p(output_dir)
      images = image_data.is_a?(Array) ? image_data : [image_data]
      saved = images.each_with_index.map do |img, index|
        save_single_image(img, output_dir, "#{filename_prefix || default_image_prefix}_#{index + 1}")
      end
      SmartPrompt.logger.info "Saved #{saved.size} #{provider_label} image(s) to #{output_dir}"
      saved
    end

    def save_single_image(image_data, output_dir, filename)
      if image_data[:b64_json]
        file_path = File.join(output_dir, "#{filename}.png")
        File.binwrite(file_path, Base64.decode64(image_data[:b64_json]))
      elsif image_data[:url]
        uri = URI.parse(image_data[:url])
        response = Net::HTTP.get_response(uri)
        raise Error, "Failed to download image from URL: #{response.code}" unless response.is_a?(Net::HTTPSuccess)

        ext = case response["content-type"]
              when "image/jpeg", "image/jpg" then "jpg"
              when "image/png"               then "png"
              when "image/gif"               then "gif"
              when "image/webp"              then "webp"
              else "png"
              end
        file_path = File.join(output_dir, "#{filename}.#{ext}")
        File.binwrite(file_path, response.body)
      else
        raise Error, "No image data available to save"
      end
      file_path
    end

    # ---- hooks (override in adapter) -----------------------------------------

    def default_image_prefix
      "image"
    end

    def provider_label
      "Adapter"
    end
  end
end
