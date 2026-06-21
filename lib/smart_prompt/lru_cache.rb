require 'thread'

module SmartPrompt
  # LRUCache implements a Least Recently Used cache with size limit enforcement
  # Thread-safe implementation for managing session cache
  class LRUCache
    attr_reader :max_size

    def initialize(max_size = nil)
      @max_size = max_size
      @cache = {}
      @access_times = {}
      @mutex = Mutex.new
    end

    # Get a value from the cache
    # Updates access time for LRU tracking
    def get(key)
      @mutex.synchronize do
        if @cache.key?(key)
          @access_times[key] = Time.now
          @cache[key]
        else
          nil
        end
      end
    end

    # Put a value into the cache
    # Enforces size limit by evicting least recently used entry if needed
    def put(key, value)
      @mutex.synchronize do
        # If key already exists, just update it
        if @cache.key?(key)
          @cache[key] = value
          @access_times[key] = Time.now
          return value
        end

        # Enforce size limit before adding new entry
        if @max_size && @cache.size >= @max_size
          evict_lru
        end

        # Add new entry
        @cache[key] = value
        @access_times[key] = Time.now
        value
      end
    end

    # Check if a key exists in the cache
    def key?(key)
      @mutex.synchronize do
        @cache.key?(key)
      end
    end

    # Delete a key from the cache
    def delete(key)
      @mutex.synchronize do
        @access_times.delete(key)
        @cache.delete(key)
      end
    end

    # Get all keys in the cache
    def keys
      @mutex.synchronize do
        @cache.keys
      end
    end

    # Get the current size of the cache
    def size
      @mutex.synchronize do
        @cache.size
      end
    end

    # Get the least recently used key
    def lru_key
      @mutex.synchronize do
        return nil if @access_times.empty?
        @access_times.min_by { |_, time| time }&.first
      end
    end

    # Clear all entries from the cache
    def clear
      @mutex.synchronize do
        @cache.clear
        @access_times.clear
      end
    end

    # Get all values in the cache
    def values
      @mutex.synchronize do
        @cache.values
      end
    end

    # Check if cache is empty
    def empty?
      @mutex.synchronize do
        @cache.empty?
      end
    end

    # Iterate over cache entries
    def each(&block)
      @mutex.synchronize do
        @cache.each(&block)
      end
    end

    private

    # Evict the least recently used entry from the cache
    # This method is called within a mutex, so no need to synchronize again
    def evict_lru
      return if @access_times.empty?

      lru_key = @access_times.min_by { |_, time| time }&.first
      if lru_key
        @cache.delete(lru_key)
        @access_times.delete(lru_key)
        SmartPrompt.logger.info "LRU cache evicted key: #{lru_key}" if defined?(SmartPrompt.logger)
      end
    end
  end
end
