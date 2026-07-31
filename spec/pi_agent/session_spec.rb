# frozen_string_literal: true

require "tempfile"

RSpec.describe PiAgent::Session do
  # Stub pi RPC server. Recognises the subset of commands the Session uses:
  #
  #   prompt    -> acks, then streams agent_start, two message_update deltas,
  #                message_end, turn_end, agent_end, agent_settled.
  #   set_model -> validated against pi's real contract (provider + modelId);
  #                rejected if either is missing.
  #   get_*     -> acks with a data/state payload.
  #   others    -> ack only.
  #
  # `abort` is a notification (no id) and is silently accepted. Any
  # unrecognised command is rejected, so a wrong command name surfaces
  # as a CommandError rather than silently passing.
  SESSION_STUB_SERVER = <<~RUBY
    require "json"
    $stdout.sync = true

    def emit(obj) = $stdout.write(JSON.generate(obj) + "\\n")
    def ack(msg, extra = {}) = emit({ "id" => msg["id"], "type" => "response", "command" => msg["type"], "success" => true }.merge(extra))

    $stdin.each_line do |line|
      msg = JSON.parse(line)
      case msg["type"]
      when "prompt"
        ack(msg)
        emit({ "type" => "agent_start", "imagesReceived" => (msg["images"] || []).size })
        if msg["message"] == "die"
          emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "partial" } })
          exit! 1
        end
        if msg["streamingBehavior"] == "followUp"
          emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "queued" } })
          emit({ "type" => "agent_end", "messages" => [], "willRetry" => false })
          emit({ "type" => "agent_settled" })
          next
        end
        emit({ "type" => "message_start" })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "Hello" } })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " world" } })
        emit({ "type" => "message_end" })
        emit({ "type" => "turn_end" })
        emit({ "type" => "agent_end", "messages" => [], "willRetry" => msg["message"] == "retry" })
        if msg["message"] == "retry"
          emit({ "type" => "auto_retry_start", "attempt" => 1, "maxAttempts" => 3, "delayMs" => 0 })
          emit({ "type" => "agent_start" })
          emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " after retry" } })
          emit({ "type" => "agent_end", "messages" => [], "willRetry" => false })
          emit({ "type" => "auto_retry_end", "success" => true, "attempt" => 1 })
        elsif msg["message"] == "compact"
          emit({ "type" => "compaction_start", "reason" => "overflow" })
          emit({ "type" => "compaction_end", "reason" => "overflow", "willRetry" => true })
          emit({ "type" => "agent_start" })
          emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " after compaction" } })
          emit({ "type" => "agent_end", "messages" => [], "willRetry" => false })
        elsif msg["message"] == "queued continuation"
          emit({ "type" => "agent_start" })
          emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " after queued continuation" } })
          emit({ "type" => "agent_end", "messages" => [], "willRetry" => false })
        elsif msg["message"] == "slow"
          sleep 0.5
        end
        emit({ "type" => "agent_settled" })
      when "follow_up"
        # pi's raw follow_up command only queues. It does not start a run when
        # idle; an active run will drain the queue before agent_settled.
        ack(msg)
      when "steer", "set_thinking_level", "set_session_name"
        ack(msg)
      when "set_model"
        # Validate the real pi contract: provider + modelId, not a `model` field.
        if msg["provider"] && msg["modelId"]
          ack(msg, "data" => { "provider" => msg["provider"], "id" => msg["modelId"] })
        else
          emit({ "id" => msg["id"], "type" => "response", "command" => "set_model",
                 "success" => false, "error" => "set_model requires provider and modelId" })
        end
      when "cycle_model"
        ack(msg, "data" => { "model" => { "id" => "next-model" }, "thinkingLevel" => "high", "isScoped" => false })
      when "get_available_models"
        ack(msg, "data" => { "models" => [{ "provider" => "anthropic", "id" => "claude-sonnet-4-5" }] })
      when "get_available_thinking_levels"
        ack(msg, "data" => { "levels" => %w[off low medium high] })
      when "get_state"
        ack(msg, "state" => { "model" => "stub-model", "thinkingLevel" => "off" })
      when "get_messages"
        ack(msg, "data" => { "messages" => [{ "role" => "user", "content" => "hi" }] })
      when "get_last_assistant_text"
        ack(msg, "data" => { "text" => "the final answer" })
      when "compact"
        ack(msg, "data" => { "summary" => "compacted", "tokensBefore" => 1000,
                             "customInstructions" => msg["customInstructions"] })
      when "new_session"
        ack(msg, "data" => { "cancelled" => false, "parentSession" => msg["parentSession"] })
      when "switch_session"
        ack(msg, "data" => { "cancelled" => false, "sessionPath" => msg["sessionPath"] })
      when "get_session_stats"
        ack(msg, "data" => { "sessionId" => "sess-123", "sessionFile" => "/tmp/sess-123.jsonl" })
      when "get_fork_messages"
        ack(msg, "data" => { "messages" => [
                  { "entryId" => "e1", "text" => "first prompt" },
                  { "entryId" => "e2", "text" => "second prompt" }
                ] })
      when "get_entries"
        entries = [
          { "type" => "message", "id" => "e1", "parentId" => nil },
          { "type" => "message", "id" => "e2", "parentId" => "e1" }
        ]
        entries = entries.drop(1) if msg["since"] == "e1"
        ack(msg, "data" => { "entries" => entries, "leafId" => "e2" })
      when "get_tree"
        ack(msg, "data" => { "tree" => [
                  { "entry" => { "id" => "e1", "parentId" => nil },
                    "children" => [{ "entry" => { "id" => "e2", "parentId" => "e1" }, "children" => [] }] }
                ], "leafId" => "e2" })
      when "fork"
        ack(msg, "data" => { "text" => "from:\#{msg["entryId"]}", "cancelled" => false })
      when "clone"
        ack(msg, "data" => { "cancelled" => false })
      when "abort"
        # notification, no ack
      else
        # Unknown command: reject so a wrong command name surfaces as an error.
        emit({ "id" => msg["id"], "type" => "response", "command" => msg["type"],
               "success" => false, "error" => "unknown command: \#{msg["type"]}" }) if msg["id"]
      end
    end
  RUBY

  # Run the stub server as the "pi" binary: `ruby -e <stub script>`.
  def build_session(**client_opts)
    client = PiAgent::Client.new(bin: "ruby", args: ["-e", SESSION_STUB_SERVER], **client_opts)
    described_class.new(client.start)
  end

  it "streams events from a prompt via a block until agent_settled" do
    session = build_session
    types = []
    session.prompt("hi") { |event| types << event.type }

    expect(types).to eq(
      %i[agent_start message_start message_update message_update message_end turn_end agent_end agent_settled]
    )
  ensure
    session&.close
  end

  it "returns an Enumerator when called without a block" do
    session = build_session
    stream = session.prompt("hi")

    expect(stream).to be_a(Enumerator)
    deltas = stream.filter_map(&:delta)
    expect(deltas).to eq(["Hello", " world"])
  ensure
    session&.close
  end

  it "stops iterating at the terminal agent_settled event" do
    session = build_session
    last = nil
    session.prompt("hi") { |event| last = event.type }

    expect(last).to eq(:agent_settled)
  ensure
    session&.close
  end

  it "continues past agent_end through an automatic retry until agent_settled" do
    session = build_session
    events = session.prompt("retry").to_a
    types = events.map(&:type)

    expect(types.count(:agent_end)).to eq(2)
    expect(types).to include(:auto_retry_start, :auto_retry_end)
    expect(events.filter_map(&:delta)).to include(" after retry")
    expect(types.last).to eq(:agent_settled)
  ensure
    session&.close
  end

  it "continues past agent_end through overflow compaction until agent_settled" do
    session = build_session
    events = session.prompt("compact").to_a
    types = events.map(&:type)

    expect(types.count(:agent_end)).to eq(2)
    expect(types).to include(:compaction_start, :compaction_end)
    expect(events.filter_map(&:delta)).to include(" after compaction")
    expect(types.last).to eq(:agent_settled)
  ensure
    session&.close
  end

  it "continues past agent_end through a queued continuation until agent_settled" do
    session = build_session
    events = session.prompt("queued continuation").to_a
    types = events.map(&:type)

    expect(types.count(:agent_end)).to eq(2)
    expect(events.filter_map(&:delta)).to include(" after queued continuation")
    expect(types.last).to eq(:agent_settled)
  ensure
    session&.close
  end

  it "raises TransportClosedError promptly when the transport dies mid-stream" do
    session = build_session
    types = []
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    expect do
      session.prompt("die") { |event| types << event.type }
    end.to raise_error(PiAgent::TransportClosedError, /exited with status 1/)
    elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

    # Events before the death still arrive, and the stream ends far below
    # the 300s event timeout.
    expect(types).to eq(%i[agent_start message_update])
    expect(elapsed).to be < 5
  ensure
    session&.close
  end

  it "allows a new event stream after a mid-stream transport death" do
    session = build_session
    begin
      session.prompt("die") { |_| nil }
    rescue PiAgent::TransportClosedError
      nil # the death we are arranging
    end

    # The single-flight stream slot was released; the next attempt fails
    # fast on the dead transport rather than raising SessionError.
    expect { session.prompt("hi") { |_| nil } }
      .to raise_error(PiAgent::TransportClosedError)
  ensure
    session&.close
  end

  it "ends an event stream subscribed only after the transport died" do
    session = build_session
    died = Queue.new
    session.client.subscribe do |msg|
      died << msg if msg["type"] == PiAgent::Client::TRANSPORT_CLOSED_TYPE
    end
    session.client.request("prompt", message: "die").value!(timeout: 2)
    expect(died.pop(timeout: 2)).not_to be_nil # death fully observed

    # The stream subscribes after the one-shot close broadcast; the replay
    # must end it promptly (a regression here raises TimeoutError instead).
    expect { session.events(event_timeout: 5) { |_| nil } }
      .to raise_error(PiAgent::TransportClosedError, /exited with status 1/)
  ensure
    session&.close
  end

  it "rejects concurrent high-level event streams" do
    session = build_session
    first_stream = Thread.new { session.prompt("slow").to_a }
    Thread.pass until first_stream.status == "sleep" || !first_stream.status

    expect do
      session.prompt("overlap", event_timeout: 1) { |_| nil }
    end.to raise_error(PiAgent::SessionError, /Another event stream is active/)
    first_stream.join(2)
  ensure
    session&.close
  end

  it "acknowledges a steer command" do
    session = build_session
    expect { session.steer("go left") }.not_to raise_error
  ensure
    session&.close
  end

  it "acknowledges a follow_up command" do
    session = build_session
    expect { session.follow_up("and then test it") }.not_to raise_error
  ensure
    session&.close
  end

  it "drains the follow_up cycle race-free when given a block" do
    session = build_session
    # The block form uses prompt + streamingBehavior so it starts a run while
    # idle (raw follow_up would only queue) and still queues when already busy.
    types = []
    deltas = []
    session.follow_up("now run it", event_timeout: 1) do |event|
      types << event.type
      deltas << event.delta if event.delta
    end

    expect(types).to eq(%i[agent_start message_update agent_end agent_settled])
    expect(deltas).to eq(["queued"])
  ensure
    session&.close
  end

  it "rejects slash commands in block-form follow_up instead of waiting for an agent event" do
    session = build_session

    expect do
      session.follow_up("/extension-command", event_timeout: 1) { |_| nil }
    end.to raise_error(PiAgent::SessionError, /does not support slash commands/)
  ensure
    session&.close
  end

  describe "#events (prompt-less drain)" do
    it "returns an Enumerator when called without a block" do
      session = build_session
      expect(session.events).to be_a(Enumerator)
    ensure
      session&.close
    end

    it "drains an agent cycle triggered after subscribing" do
      session = build_session
      # The subscription must be live before the prompt cycle is emitted, so
      # consume `events` in a background thread, then use the low-level client
      # to trigger work without creating a second high-level event stream.
      types = []
      consumer = Thread.new { session.events { |event| types << event.type } }
      Thread.pass until consumer.status == "sleep" || !consumer.status # subscribed, blocked on the queue
      session.client.request("prompt", message: "now run it").value!(timeout: 1)
      consumer.join(5)

      expect(types).to eq(
        %i[agent_start message_start message_update message_update message_end turn_end agent_end agent_settled]
      )
    ensure
      session&.close
    end
  end

  it "sends abort as a fire-and-forget notification" do
    session = build_session
    expect { session.abort }.not_to raise_error
  ensure
    session&.close
  end

  it "sets the model from a provider/modelId string" do
    session = build_session
    expect { session.set_model("anthropic/claude-sonnet-4-5") }.not_to raise_error
  ensure
    session&.close
  end

  it "sets the model from separate provider and modelId arguments" do
    session = build_session
    expect { session.set_model("anthropic", "claude-sonnet-4-5") }.not_to raise_error
  ensure
    session&.close
  end

  it "cycles to the next model" do
    session = build_session
    result = session.cycle_model

    expect(result["model"]).to eq({ "id" => "next-model" })
    expect(result["thinkingLevel"]).to eq("high")
  ensure
    session&.close
  end

  it "lists available models" do
    session = build_session
    expect(session.available_models).to eq([{ "provider" => "anthropic", "id" => "claude-sonnet-4-5" }])
  ensure
    session&.close
  end

  it "sets the thinking level" do
    session = build_session
    expect { session.set_thinking("medium") }.not_to raise_error
  ensure
    session&.close
  end

  it "lists available thinking levels" do
    session = build_session
    expect(session.available_thinking_levels).to eq(%w[off low medium high])
  ensure
    session&.close
  end

  it "fetches agent state" do
    session = build_session
    state = session.get_state

    expect(state["state"]).to eq({ "model" => "stub-model", "thinkingLevel" => "off" })
  ensure
    session&.close
  end

  it "fetches the conversation messages" do
    session = build_session
    expect(session.messages).to eq([{ "role" => "user", "content" => "hi" }])
  ensure
    session&.close
  end

  it "fetches the last assistant text" do
    session = build_session
    expect(session.last_assistant_text).to eq("the final answer")
  ensure
    session&.close
  end

  it "runs a prompt and returns the final assistant text" do
    session = build_session
    expect(session.run("hi")).to eq("the final answer")
  ensure
    session&.close
  end

  it "yields events to a block while running" do
    session = build_session
    types = []
    session.run("hi") { |event| types << event.type }

    expect(types.last).to eq(:agent_settled)
  ensure
    session&.close
  end

  it "compacts the conversation context" do
    session = build_session
    result = session.compact(custom_instructions: "keep code")

    expect(result["summary"]).to eq("compacted")
    expect(result["customInstructions"]).to eq("keep code")
  ensure
    session&.close
  end

  it "starts a new session" do
    session = build_session
    result = session.new_session(parent_session: "/tmp/parent.jsonl")

    expect(result["cancelled"]).to be false
    expect(result["parentSession"]).to eq("/tmp/parent.jsonl")
  ensure
    session&.close
  end

  it "switches to a different session file" do
    session = build_session
    result = session.switch_session("/tmp/other.jsonl")

    expect(result["cancelled"]).to be false
    expect(result["sessionPath"]).to eq("/tmp/other.jsonl")
  ensure
    session&.close
  end

  it "supports two sequential prompts on the same session" do
    session = build_session
    first = session.prompt("one").count
    second = session.prompt("two").count

    expect(first).to eq(8)
    expect(second).to eq(8)
  ensure
    session&.close
  end

  it "lists fork messages" do
    session = build_session
    messages = session.fork_messages

    expect(messages).to eq(
      [
        { "entryId" => "e1", "text" => "first prompt" },
        { "entryId" => "e2", "text" => "second prompt" }
      ]
    )
  ensure
    session&.close
  end

  it "lists session entries in append order" do
    session = build_session
    result = session.entries

    expect(result["entries"].map { |e| e["id"] }).to eq(%w[e1 e2])
    expect(result["leafId"]).to eq("e2")
  ensure
    session&.close
  end

  it "passes a since cursor to get_entries" do
    session = build_session
    result = session.entries(since: "e1")

    expect(result["entries"].map { |e| e["id"] }).to eq(%w[e2])
  ensure
    session&.close
  end

  it "fetches the session tree" do
    session = build_session
    result = session.tree

    expect(result["tree"].first["entry"]["id"]).to eq("e1")
    expect(result["tree"].first["children"].first["entry"]["id"]).to eq("e2")
    expect(result["leafId"]).to eq("e2")
  ensure
    session&.close
  end

  it "forks from a previous message and returns the forked-from text" do
    session = build_session
    result = session.fork("e1")

    expect(result["text"]).to eq("from:e1")
    expect(result["cancelled"]).to be false
  ensure
    session&.close
  end

  it "clones the current branch" do
    session = build_session
    result = session.clone_session

    expect(result["cancelled"]).to be false
  ensure
    session&.close
  end

  it "sets the session name" do
    session = build_session
    expect { session.set_session_name("my-feature") }.not_to raise_error
  ensure
    session&.close
  end

  it "fetches session stats" do
    session = build_session
    stats = session.session_stats

    expect(stats["sessionId"]).to eq("sess-123")
    expect(stats["sessionFile"]).to eq("/tmp/sess-123.jsonl")
  ensure
    session&.close
  end

  describe "images" do
    def images_received(session, images)
      start = session.prompt("look", images: images).find { |e| e.type == :agent_start }
      start["imagesReceived"]
    end

    it "sends an Image object as an ImageContent attachment" do
      session = build_session
      image = PiAgent::Image.from_bytes("fakebytes", mime_type: "image/png")
      expect(images_received(session, [image])).to eq(1)
    ensure
      session&.close
    end

    it "accepts a raw ImageContent hash" do
      session = build_session
      hash = { "type" => "image", "data" => "abc", "mimeType" => "image/png" }
      expect(images_received(session, [hash])).to eq(1)
    ensure
      session&.close
    end

    it "accepts a file path string" do
      session = build_session
      file = Tempfile.new(["pic", ".png"])
      file.binmode
      file.write("fakebytes")
      file.flush
      expect(images_received(session, [file.path])).to eq(1)
    ensure
      session&.close
      file&.close!
    end

    it "sends multiple images" do
      session = build_session
      a = PiAgent::Image.from_bytes("a", mime_type: "image/png")
      b = PiAgent::Image.from_bytes("b", mime_type: "image/jpeg")
      expect(images_received(session, [a, b])).to eq(2)
    ensure
      session&.close
    end

    it "omits the images field when none are given" do
      session = build_session
      expect(images_received(session, nil)).to eq(0)
    ensure
      session&.close
    end

    it "raises ArgumentError for an unsupported image input" do
      session = build_session
      expect { session.prompt("look", images: [42]).to_a }
        .to raise_error(ArgumentError, /Unsupported image/)
    ensure
      session&.close
    end
  end
end
