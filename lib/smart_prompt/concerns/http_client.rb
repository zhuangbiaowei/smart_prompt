require "json"
require "net/http"
require "uri"

module SmartPrompt
  # Shared Net::HTTP plumbing for Net::HTTP-style adapters (ZhipuAI, SenseNova,
  # SiliconFlow). Each previously carried its own copy of post/get/binary/multipart
  # + SSE stream helpers, differing only in the provider label sprinkled through
  # log/exception messages — which the `provider_label` hook now supplies.
  #
  # http_post_multipart takes the general 5-arg shape (file_field + mime); Zhipu's
  # ASR call site uses a 3-arg shim defined on the adapter itself.
  module HTTPClient
    def http_post_json(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 240
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body.to_json
      SmartPrompt.logger.debug "#{provider_label} POST #{uri} body=#{body.to_json}"
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        SmartPrompt.logger.error "#{provider_label} API error: #{resp.code} - #{resp.body}"
        raise LLMAPIError, "#{provider_label} API error: #{resp.code} - #{resp.body}"
      end
    end

    def http_get_json(url)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 60
      req = Net::HTTP::Get.new(uri.request_uri)
      req["Authorization"] = "Bearer #{@api_key}"
      SmartPrompt.logger.debug "#{provider_label} GET #{uri}"
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        raise LLMAPIError, "#{provider_label} API error: #{resp.code} - #{resp.body}"
      end
    end

    # Returns the raw response body bytes (for binary payloads like TTS audio).
    def http_post_binary(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 120
      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body.to_json
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body
      else
        raise LLMAPIError, "#{provider_label} TTS API error: #{resp.code} - #{resp.body}"
      end
    end

    # multipart/form-data POST with a file upload (ASR, voice upload). Returns parsed JSON.
    def http_post_multipart(url, form, file_field, file_path, mime)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 180

      boundary = "----SmartPrompt#{object_id}"
      body = +""
      form.each do |k, v|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"#{k}\"\r\n\r\n"
        body << "#{v}\r\n"
      end
      File.open(file_path, "rb") do |f|
        body << "--#{boundary}\r\n"
        body << "Content-Disposition: form-data; name=\"#{file_field}\"; filename=\"#{File.basename(file_path)}\"\r\n"
        body << "Content-Type: #{mime}\r\n\r\n"
        body << f.read
        body << "\r\n"
      end
      body << "--#{boundary}--\r\n"

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "multipart/form-data; boundary=#{boundary}"
      req["Authorization"] = "Bearer #{@api_key}"
      req.body = body
      resp = http.request(req)
      if resp.is_a?(Net::HTTPSuccess)
        resp.body.to_s.empty? ? {} : JSON.parse(resp.body)
      else
        raise LLMAPIError, "#{provider_label} multipart API error: #{resp.code} - #{resp.body}"
      end
    end

    # POST with stream:true and yield each parsed SSE `data:` payload to the block.
    def stream_chat(url, body)
      uri = URI.parse(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      http.open_timeout = 30
      http.read_timeout = 300

      req = Net::HTTP::Post.new(uri.request_uri)
      req["Content-Type"]  = "application/json"
      req["Authorization"] = "Bearer #{@api_key}"
      req["Accept"]        = "text/event-stream"
      req.body = body.to_json

      buffer = +""
      done = false
      http.request(req) do |response|
        unless response.is_a?(Net::HTTPSuccess)
          raise LLMAPIError, "#{provider_label} stream error: #{response.code} - #{response.body}"
        end
        response.read_body do |segment|
          break if done
          buffer << segment
          while (idx = buffer.index("\n"))
            line = buffer.slice!(0, idx + 1).strip
            next if line.empty? || !line.start_with?("data:")
            payload = line.sub(/\Adata:\s*/, "")
            if payload == "[DONE]"
              done = true
              break
            end
            begin
              yield JSON.parse(payload)
            rescue JSON::ParserError
              next
            end
          end
        end
      end
    end
  end
end
