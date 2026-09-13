require 'minitest/autorun'
require './lib/smart_prompt'

# Regression tests for the history/session fixes that were previously carried
# as monkey-patches downstream:
#   1. Message serialization must keep tool_calls / tool_call_id / reasoning_content.
#   2. Session trimming must not split an assistant(tool_calls) from its tool results.
#   3. HistoryManager must upsert (not accumulate) the durable system message.
#   4. WorkerContext must merge the transient prompt with persisted history.
class HistoryFixesTest < Minitest::Test
  # --- 1. Message serialization --------------------------------------------

  def test_message_round_trip_preserves_tool_calls_and_reasoning
    msg = SmartPrompt::Message.new(
      role: "assistant", content: "", reasoning_content: "think",
      tool_calls: [{ id: "call-1", type: "function", function: { name: "read", arguments: "{}" } }]
    )
    h = msg.to_h

    assert_equal "think", h[:reasoning_content]
    assert_equal "call-1", h[:tool_calls].first[:id]
  end

  def test_message_round_trip_preserves_tool_call_id
    h = SmartPrompt::Message.new(role: "tool", tool_call_id: "call-1", content: "result").to_h
    assert_equal "call-1", h[:tool_call_id]
  end

  def test_message_without_extra_fields_has_no_extra_keys
    h = SmartPrompt::Message.new(role: "user", content: "hi").to_h
    refute h.key?(:tool_calls)
    refute h.key?(:tool_call_id)
    refute h.key?(:reasoning_content)
  end

  # --- 2. Session pair trimming --------------------------------------------

  def append_tool_pair(session, idx)
    session.add_message(
      role: "assistant", content: "",
      tool_calls: [{ id: "call_#{idx}", type: "function",
                     function: { name: "read", arguments: "{}" } }]
    )
    session.add_message(role: "tool", tool_call_id: "call_#{idx}", content: "ok#{idx}")
  end

  def assert_no_orphan_tool(session)
    ids = session.messages
                 .select { |m| m.respond_to?(:tool_calls) && m.tool_calls }
                 .flat_map { |m| m.tool_calls.map { |tc| tc[:id] || tc["id"] } }
    orphans = session.messages.select do |m|
      m.role.to_s == "tool" && !ids.include?(m.tool_call_id)
    end
    assert_empty orphans, "orphan tool messages must never survive trimming"
  end

  def test_message_count_trim_keeps_tool_pairs
    session = SmartPrompt::Session.new("s", { max_messages: 4 })
    session.add_message(role: "system", content: "SYS")
    11.times { |i| append_tool_pair(session, i) }

    assert_no_orphan_tool(session)
    assert_operator session.messages.reject(&:system_message?).length, :<=, 4
    assert session.messages.any? { |m| m.respond_to?(:tool_calls) && m.tool_calls },
           "most recent tool pair should be retained"
  end

  def test_token_trim_keeps_tool_pairs
    session = SmartPrompt::Session.new("s", { max_tokens: 1 })
    session.add_message(role: "system", content: "SYS")
    5.times { |i| append_tool_pair(session, i) }

    assert_no_orphan_tool(session)
  end

  # --- 3. HistoryManager system upsert --------------------------------------

  def test_upsert_system_message_keeps_single_copy
    manager = SmartPrompt::HistoryManager.new(
      cache_size: 10,
      session_defaults: { max_messages: 100, max_tokens: 100_000 },
      persistence: { enabled: false }
    )

    assert manager.upsert_system_message("sid", "stable-v1")
    refute manager.upsert_system_message("sid", "stable-v1"), "identical content is a no-op"
    assert manager.upsert_system_message("sid", "stable-v2")

    context = manager.get_context("sid")
    systems = context.select(&:system_message?)
    assert_equal 1, systems.length
    assert_equal "stable-v2", systems.first.content
  end

  # --- 4. WorkerContext transient history merge -----------------------------

  class FakeConversation
    attr_reader :messages, :sent_params, :sent_messages

    def initialize
      @messages = [{ role: "system", content: "current system" }]
    end

    def prompt(content, with_history: false)
      raise "transient prompt must not be persisted" if with_history

      @messages << { role: "user", content: content }
    end

    def send_msg(params)
      @sent_params = params
      @sent_messages = @messages.dup
      "ok"
    end
  end

  def test_with_history_merges_history_and_transient_prompt
    engine = Struct.new(:history_messages).new(
      [
        { role: "system", content: "persisted system" },
        { role: "assistant", content: "previous tool turn" }
      ]
    )
    conversation = FakeConversation.new
    context = SmartPrompt::WorkerContext.new(
      conversation, { with_history: true, session_id: "task/history/session" }, engine
    )

    context.transient_prompt("current step")
    assert_equal "ok", context.send_msg

    assert_equal false, conversation.sent_params[:with_history]
    assert_equal %w[system assistant user],
                 conversation.sent_messages.map { |m| m[:role] }
    assert_equal "current system", conversation.sent_messages.first[:content]
    assert_equal "current step", conversation.sent_messages.last[:content]
  end

  def test_with_history_without_transient_keeps_history_send
    engine = Struct.new(:history_messages).new([{ role: "user", content: "persisted prompt" }])
    conversation = FakeConversation.new
    context = SmartPrompt::WorkerContext.new(
      conversation, { with_history: true, session_id: "task/history/session" }, engine
    )

    assert_equal "ok", context.send_msg
    assert_equal true, conversation.sent_params[:with_history]
  end
end
