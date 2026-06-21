require 'minitest/autorun'
require './lib/smart_prompt'

# Tests for LRU cache functionality in HistoryManager
class LRUCacheTest < Minitest::Test
  def test_cache_size_limit_enforcement
    # Create manager with small cache size
    manager = SmartPrompt::HistoryManager.new(cache_size: 3)
    
    # Add 3 sessions (at limit)
    manager.add_message("session1", { role: "user", content: "Message 1" })
    manager.add_message("session2", { role: "user", content: "Message 2" })
    manager.add_message("session3", { role: "user", content: "Message 3" })
    
    assert_equal 3, manager.session_ids.length
    
    # Add 4th session - should evict least recently used (session1)
    manager.add_message("session4", { role: "user", content: "Message 4" })
    
    assert_equal 3, manager.session_ids.length
    assert !manager.session_exists?("session1"), "Session1 should have been evicted"
    assert manager.session_exists?("session2")
    assert manager.session_exists?("session3")
    assert manager.session_exists?("session4")
  end
  
  def test_lru_eviction_order
    manager = SmartPrompt::HistoryManager.new(cache_size: 3)
    
    # Add 3 sessions
    manager.add_message("session1", { role: "user", content: "Message 1" })
    sleep 0.01
    manager.add_message("session2", { role: "user", content: "Message 2" })
    sleep 0.01
    manager.add_message("session3", { role: "user", content: "Message 3" })
    
    # Access session1 to make it more recently used
    sleep 0.01
    manager.get_context("session1")
    
    # Add 4th session - should evict session2 (now least recently used)
    manager.add_message("session4", { role: "user", content: "Message 4" })
    
    assert manager.session_exists?("session1"), "Session1 should still exist (was accessed)"
    assert !manager.session_exists?("session2"), "Session2 should have been evicted"
    assert manager.session_exists?("session3")
    assert manager.session_exists?("session4")
  end
  
  def test_lru_session_id_tracking
    manager = SmartPrompt::HistoryManager.new(cache_size: 5)
    
    # Add sessions with delays to ensure different access times
    manager.add_message("session1", { role: "user", content: "Message 1" })
    sleep 0.01
    manager.add_message("session2", { role: "user", content: "Message 2" })
    sleep 0.01
    manager.add_message("session3", { role: "user", content: "Message 3" })
    
    # session1 should be the least recently used
    assert_equal "session1", manager.lru_session_id
    
    # Access session1 to update its access time
    manager.get_context("session1")
    
    # Now session2 should be the least recently used
    assert_equal "session2", manager.lru_session_id
  end
  
  def test_no_eviction_when_under_limit
    manager = SmartPrompt::HistoryManager.new(cache_size: 10)
    
    # Add 5 sessions (under limit)
    5.times do |i|
      manager.add_message("session#{i}", { role: "user", content: "Message #{i}" })
    end
    
    assert_equal 5, manager.session_ids.length
    
    # All sessions should still exist
    5.times do |i|
      assert manager.session_exists?("session#{i}")
    end
  end
  
  def test_cache_with_nil_size_no_eviction
    # When cache_size is nil, no eviction should occur
    manager = SmartPrompt::HistoryManager.new(cache_size: nil)
    
    # Add many sessions
    20.times do |i|
      manager.add_message("session#{i}", { role: "user", content: "Message #{i}" })
    end
    
    # All sessions should still exist
    assert_equal 20, manager.session_ids.length
  end
  
  def test_access_updates_lru_order
    manager = SmartPrompt::HistoryManager.new(cache_size: 3)
    
    # Add 3 sessions
    manager.add_message("session1", { role: "user", content: "Message 1" })
    sleep 0.01
    manager.add_message("session2", { role: "user", content: "Message 2" })
    sleep 0.01
    manager.add_message("session3", { role: "user", content: "Message 3" })
    
    # Access session1 multiple times
    sleep 0.01
    manager.get_context("session1")
    sleep 0.01
    manager.add_message("session1", { role: "user", content: "Another message" })
    
    # Add 4th session - session2 should be evicted (least recently used)
    manager.add_message("session4", { role: "user", content: "Message 4" })
    
    assert manager.session_exists?("session1")
    assert !manager.session_exists?("session2")
    assert manager.session_exists?("session3")
    assert manager.session_exists?("session4")
  end
  
  def test_get_session_updates_access_time
    manager = SmartPrompt::HistoryManager.new(cache_size: 3)
    
    # Add 3 sessions
    manager.add_message("session1", { role: "user", content: "Message 1" })
    sleep 0.01
    manager.add_message("session2", { role: "user", content: "Message 2" })
    sleep 0.01
    manager.add_message("session3", { role: "user", content: "Message 3" })
    
    # Use get_session to access session1
    sleep 0.01
    manager.get_session("session1")
    
    # Add 4th session - session2 should be evicted
    manager.add_message("session4", { role: "user", content: "Message 4" })
    
    assert manager.session_exists?("session1")
    assert !manager.session_exists?("session2")
  end
end
