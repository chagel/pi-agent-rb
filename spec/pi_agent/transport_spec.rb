# frozen_string_literal: true

RSpec.describe PiAgent::Transport do
  # Tiny Ruby subprocess that echoes each stdin line to stdout. Sufficient
  # to exercise the JSONL round trip without requiring pi or any real agent.
  ECHO_SCRIPT = <<~RUBY
    $stdout.sync = true
    $stdin.each_line { |line| $stdout.write(line) }
  RUBY

  # Subprocess that emits two JSON lines on stdout and exits.
  EMITTER_SCRIPT = <<~RUBY
    $stdout.sync = true
    $stdout.write %({"type":"a"}\\n)
    $stdout.write %({"type":"b","x":1}\\n)
  RUBY

  it "round-trips JSON messages through stdin and stdout" do
    received = Queue.new
    transport = described_class.new(
      command: ["ruby", "-e", ECHO_SCRIPT],
      on_message: ->(msg) { received << msg }
    ).start

    transport.write({ "hello" => "world" })
    expect(received.pop(timeout: 2)).to eq({ "hello" => "world" })

    transport.write({ "n" => 42, "nested" => { "a" => [1, 2] } })
    expect(received.pop(timeout: 2)).to eq({ "n" => 42, "nested" => { "a" => [1, 2] } })
  ensure
    transport&.close
  end

  it "delivers multiple notifications from the server stream" do
    received = Queue.new
    transport = described_class.new(
      command: ["ruby", "-e", EMITTER_SCRIPT],
      on_message: ->(msg) { received << msg }
    ).start

    expect(received.pop(timeout: 2)).to eq({ "type" => "a" })
    expect(received.pop(timeout: 2)).to eq({ "type" => "b", "x" => 1 })
  ensure
    transport&.close
  end

  it "raises ProtocolError when writing after close" do
    transport = described_class.new(command: ["ruby", "-e", ECHO_SCRIPT]).start
    transport.close
    expect { transport.write({ "x" => 1 }) }.to raise_error(PiAgent::ProtocolError)
  end

  it "is idempotent on repeated close" do
    transport = described_class.new(command: ["ruby", "-e", ECHO_SCRIPT]).start
    transport.close
    expect { transport.close }.not_to raise_error
  end

  it "forwards stderr lines to on_stderr" do
    received = Queue.new
    stderr_script = '$stderr.write %(boom\\n)'
    transport = described_class.new(
      command: ["ruby", "-e", stderr_script],
      on_stderr: ->(line) { received << line }
    ).start

    expect(received.pop(timeout: 2)).to eq("boom")
  ensure
    transport&.close
  end

  it "surfaces invalid JSON to stderr handler rather than crashing" do
    received_stderr = Queue.new
    received_msg = Queue.new
    junk_script = '$stdout.write %(not json\\n{"ok":true}\\n)'
    transport = described_class.new(
      command: ["ruby", "-e", junk_script],
      on_message: ->(msg) { received_msg << msg },
      on_stderr: ->(line) { received_stderr << line }
    ).start

    expect(received_stderr.pop(timeout: 2)).to include("invalid JSON")
    expect(received_msg.pop(timeout: 2)).to eq({ "ok" => true })
  ensure
    transport&.close
  end
end
