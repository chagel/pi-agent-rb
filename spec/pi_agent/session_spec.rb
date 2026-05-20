# frozen_string_literal: true

RSpec.describe PiAgent::Session do
  # Stub pi RPC server. Recognises the subset of commands the Session uses:
  #
  #   prompt  -> acks, then streams agent_start, two message_update deltas,
  #              message_end, turn_end, agent_end.
  #   steer   -> acks only.
  #   set_*   -> acks only.
  #   get_state -> acks with a state payload.
  #
  # `abort` is a notification (no id) and is silently accepted.
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
        emit({ "type" => "agent_start" })
        emit({ "type" => "message_start" })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => "Hello" } })
        emit({ "type" => "message_update", "assistantMessageEvent" => { "type" => "text_delta", "delta" => " world" } })
        emit({ "type" => "message_end" })
        emit({ "type" => "turn_end" })
        emit({ "type" => "agent_end", "messages" => [] })
      when "steer", "set_model", "set_thinking"
        ack(msg)
      when "get_state"
        ack(msg, "state" => { "model" => "stub-model", "thinkingLevel" => "off" })
      when "abort"
        # notification, no ack
      else
        ack(msg)
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

  it "sets the model" do
    session = build_session
    expect { session.set_model("anthropic/claude-sonnet-4-5") }.not_to raise_error
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

  it "supports two sequential prompts on the same session" do
    session = build_session
    first = session.prompt("one").count
    second = session.prompt("two").count

    expect(first).to eq(7)
    expect(second).to eq(7)
  ensure
    session&.close
  end
end
