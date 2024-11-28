module SmartPrompt
    module APIHandler
        MAX_RETRIES = 3
        RETRY_OPTIONS = {
          tries: MAX_RETRIES,
          base_interval: 1,
          max_interval: 10,
          rand_factor: 0.5,
          on: [
            Errno::ECONNRESET,
            Errno::ECONNABORTED,
            Errno::EPIPE,
            Errno::ETIMEDOUT
          ]
        }
    end
end