# frozen_string_literal: true

require "tmpdir"
require "json"

RSpec.describe PiAgent::Transport::Subprocess do
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

  describe "on_close" do
    it "reports a child that exits on its own, exactly once" do
      reasons = Queue.new
      transport = described_class.new(
        command: ["ruby", "-e", EMITTER_SCRIPT],
        on_message: ->(msg) {},
        on_close: ->(reason) { reasons << reason }
      ).start

      expect(reasons.pop(timeout: 2)).to match(/exited with status 0/)
      expect(reasons.pop(timeout: 0.3)).to be_nil
    ensure
      transport&.close
    end

    it "delivers pending stdout messages before reporting the close" do
      events = Queue.new
      transport = described_class.new(
        command: ["ruby", "-e", EMITTER_SCRIPT],
        on_message: ->(msg) { events << [:message, msg] },
        on_close: ->(reason) { events << [:close, reason] }
      ).start

      expect(events.pop(timeout: 2).first).to eq(:message)
      expect(events.pop(timeout: 2).first).to eq(:message)
      expect(events.pop(timeout: 2).first).to eq(:close)
    ensure
      transport&.close
    end

    it "includes a nonzero exit status in the reason" do
      reasons = Queue.new
      transport = described_class.new(
        command: ["ruby", "-e", "exit 3"],
        on_close: ->(reason) { reasons << reason }
      ).start

      expect(reasons.pop(timeout: 2)).to match(/exited with status 3/)
    ensure
      transport&.close
    end

    it "reports the signal when the child is killed" do
      reasons = Queue.new
      transport = described_class.new(
        command: ["ruby", "-e", "sleep"],
        on_close: ->(reason) { reasons << reason }
      ).start

      Process.kill("KILL", transport.pid)
      expect(reasons.pop(timeout: 2)).to match(/terminated by signal 9/)
    ensure
      transport&.close
    end

    it "reports the exit even when a descendant holds stdout open" do
      reasons = Queue.new
      # The child spawns a grandchild that inherits the stdout pipe, then
      # exits: the pipe never reaches EOF, so only the independent exit
      # watcher can observe the death.
      orphaning_script = 'Process.detach(spawn("ruby", "-e", "sleep 5")); exit 0'
      transport = described_class.new(
        command: ["ruby", "-e", orphaning_script],
        on_close: ->(reason) { reasons << reason }
      ).start

      expect(reasons.pop(timeout: 4)).to match(/exited with status 0/)
    ensure
      transport&.close
    end

    it "does not report a caller-initiated close as a death" do
      reasons = Queue.new
      transport = described_class.new(
        command: ["ruby", "-e", ECHO_SCRIPT],
        on_close: ->(reason) { reasons << reason }
      ).start

      transport.close
      expect(reasons.pop(timeout: 0.3)).to be_nil
    end
  end

  it "runs the child process in the given working directory" do
    Dir.mktmpdir do |dir|
      received = Queue.new
      pwd_script = 'require "json"; $stdout.sync = true; $stdout.write(JSON.generate({ "pwd" => Dir.pwd }) + "\\n")'
      transport = described_class.new(
        command: ["ruby", "-e", pwd_script], cwd: dir,
        on_message: ->(msg) { received << msg }
      ).start

      expect(File.realpath(received.pop(timeout: 2)["pwd"])).to eq(File.realpath(dir))
    ensure
      transport&.close
    end
  end
end
