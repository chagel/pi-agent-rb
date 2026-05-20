# frozen_string_literal: true

# Client tests against a stub subprocess. Live integration with `pi --mode rpc`
# is gated behind PI_LIVE_TEST=1 and lives in a separate spec.
RSpec.describe PiAgent::Client do
  # Stub server: parses each request line and responds with
  #   {"id":"<id>","type":"response","command":"<type>","success":true,"echo":<params>}
  # If `type == "notify_only"`, no response is sent.
  # If `type == "broadcast"`, sends two notifications instead.
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
      else
        resp = { "id" => msg["id"], "type" => "response", "command" => msg["type"], "success" => true }
        resp["echo"] = msg.reject { |k, _| %w[id type].include?(k) }
        $stdout.write JSON.generate(resp) + "\\n"
      end
    end
  RUBY

  def client
    stub = described_class.allocate
    stub.instance_variable_set(:@bin, "ruby")
    stub.instance_variable_set(:@args, ["-e", CLIENT_STUB_SERVER])
    stub.instance_variable_set(:@env, {})
    stub.instance_variable_set(:@pending, {})
    stub.instance_variable_set(:@pending_mutex, Mutex.new)
    stub.instance_variable_set(:@next_id, 0)
    stub.instance_variable_set(:@subscribers, [])
    stub.instance_variable_set(:@subscribers_mutex, Mutex.new)
    stub.start
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
end
