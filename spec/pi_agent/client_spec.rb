# frozen_string_literal: true

# Client tests against a stub subprocess. Live integration with `pi --mode rpc`
# is gated behind PI_LIVE_TEST=1 and lives in a separate spec.
RSpec.describe PiAgent::Client do
  # Stub server: parses each request line and responds with
  #   {"id":"<id>","type":"response","command":"<type>","success":true,"echo":<params>}
  # If `type == "notify_only"`, no response is sent.
  # If `type == "broadcast"`, sends two notifications instead.
  # If `type == "fail"`, responds with success:false and an error.
  CLIENT_STUB_SERVER = <<~RUBY
    require "json"
    $stdout.sync = true
    $stdin.each_line do |line|
      msg = JSON.parse(line)
      case msg["type"]
      when "notify_only"
        next
      when "broadcast"
        $stdout.write JSON.generate({ "type" => "agent_start" }) + "\\n"
        $stdout.write JSON.generate({ "type" => "agent_end" }) + "\\n"
      when "fail"
        resp = { "id" => msg["id"], "type" => "response", "command" => "fail",
                 "success" => false, "error" => "boom: bad command" }
        $stdout.write JSON.generate(resp) + "\\n"
      else
        resp = { "id" => msg["id"], "type" => "response", "command" => msg["type"], "success" => true }
        resp["echo"] = msg.reject { |k, _| %w[id type].include?(k) }
        $stdout.write JSON.generate(resp) + "\\n"
      end
    end
  RUBY

  # Run the stub server as the "pi" binary: `ruby -e <stub script>`.
  def client
    described_class.new(bin: "ruby", args: ["-e", CLIENT_STUB_SERVER]).start
  end

  it "completes a request/response round trip" do
    c = client
    future = c.request("ping", foo: "bar")
    response = future.value!(timeout: 2)

    expect(response["type"]).to eq("response")
    expect(response["command"]).to eq("ping")
    expect(response["success"]).to be true
    expect(response["echo"]).to eq({ "foo" => "bar" })
  ensure
    c&.close
  end

  it "correlates concurrent in-flight requests by id" do
    c = client
    f1 = c.request("first")
    f2 = c.request("second")

    expect(f1.value!(timeout: 2)["command"]).to eq("first")
    expect(f2.value!(timeout: 2)["command"]).to eq("second")
  ensure
    c&.close
  end

  it "delivers notifications to subscribers" do
    c = client
    received = Queue.new
    c.subscribe { |msg| received << msg }
    c.notify("broadcast")

    expect(received.pop(timeout: 2)).to eq({ "type" => "agent_start" })
    expect(received.pop(timeout: 2)).to eq({ "type" => "agent_end" })
  ensure
    c&.close
  end

  it "supports unsubscribe" do
    c = client
    received = Queue.new
    handle = c.subscribe { |msg| received << msg }
    c.unsubscribe(handle)
    c.notify("broadcast")

    # Give the server enough time to push the notifications; assert none landed
    expect(received.pop(timeout: 0.3)).to be_nil
  ensure
    c&.close
  end

  it "rejects pending futures with ProtocolError on close" do
    c = client
    future = c.request("notify_only") # stub server never replies
    c.close
    expect { future.value!(timeout: 1) }.to raise_error(PiAgent::ProtocolError, /closed/)
  end

  it "rejects the future with CommandError when a command fails" do
    c = client
    expect { c.request("fail").value!(timeout: 2) }
      .to raise_error(PiAgent::CommandError, /boom: bad command/)
  ensure
    c&.close
  end

  it "exposes the failing command name on CommandError" do
    c = client
    c.request("fail").value!(timeout: 2)
  rescue PiAgent::CommandError => e
    expect(e.command).to eq("fail")
  ensure
    c&.close
  end

  describe "transport injection" do
    it "drives an injected transport instead of spawning pi" do
      # A custom factory means no local `pi` binary is resolved — the
      # client never touches PATH. Here the factory builds a subprocess
      # transport for the stub server, proving the seam works end to end.
      factory = lambda do |on_message:, on_stderr:|
        PiAgent::Transport::Subprocess.new(
          command: ["ruby", "-e", CLIENT_STUB_SERVER],
          on_message: on_message, on_stderr: on_stderr
        )
      end

      c = described_class.new(transport_factory: factory).start
      response = c.request("ping", foo: "bar").value!(timeout: 2)

      expect(response["command"]).to eq("ping")
      expect(response["echo"]).to eq({ "foo" => "bar" })
    ensure
      c&.close
    end

    it "does not resolve a pi binary when a transport_factory is given" do
      factory = lambda do |on_message:, on_stderr:|
        PiAgent::Transport::Subprocess.new(
          command: ["ruby", "-e", CLIENT_STUB_SERVER],
          on_message: on_message, on_stderr: on_stderr
        )
      end

      c = described_class.new(bin: "definitely-not-pi-xyz", transport_factory: factory)
      expect(c.bin).to be_nil
    end
  end
end
