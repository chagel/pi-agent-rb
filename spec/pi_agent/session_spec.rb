# frozen_string_literal: true

require "tempfile"

RSpec.describe PiAgent::Session do
  # Stub pi RPC server. Recognises the subset of commands the Session uses:
  #
  #   prompt    -> acks, then streams agent_start, two message_update deltas,
  #                message_end, turn_end, agent_end.
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
        emit({ "type" => "message_start" })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "Hello" } })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " world" } })
        emit({ "type" => "message_end" })
        emit({ "type" => "turn_end" })
        emit({ "type" => "agent_end", "messages" => [] })
      when "steer", "follow_up", "set_thinking_level", "set_session_name"
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

  it "streams events from a prompt via a block until agent_end" do
    session = build_session
    types = []
    session.prompt("hi") { |event| types << event.type }

    expect(types).to eq(%i[agent_start message_start message_update message_update message_end turn_end agent_end])
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

  it "stops iterating at the terminal agent_end event" do
    session = build_session
    last = nil
    session.prompt("hi") { |event| last = event.type }

    expect(last).to eq(:agent_end)
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

    expect(types.last).to eq(:agent_end)
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

    expect(first).to eq(7)
    expect(second).to eq(7)
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
