# frozen_string_literal: true

# Client tests against a stub subprocess. Live integration with `pi --mode rpc`
# is gated behind PI_LIVE_TEST=1 and lives in a separate spec.
RSpec.describe PiAgent::Client do
  # Stub server: parses each request line and responds with
  #   {"id":"<id>","type":"response","command":"<type>","success":true,"echo":<params>}
  # If `type == "notify_only"`, no response is sent.
  # If `type == "broadcast"`, sends two notifications instead.
  # If `type == "fail"`, responds with success:false and an error.
  # If `type == "die"`, exits with status 1 without responding.
  CLIENT_STUB_SERVER = <<~RUBY
    require "json"
    $stdout.sync = true
    $stdin.each_line do |line|
      msg = JSON.parse(line)
      case msg["type"]
      when "notify_only"
        next
      when "die"
        exit! 1
      when "broadcast"
        $stdout.write JSON.generate({ "type" => "agent_start" }) + "\\n"
        $stdout.write JSON.generate({ "type" => "agent_end" }) + "\\n"
      when "fail"
        resp = { "id" => msg["id"], "type" => "response", "command" => "fail",
                 "success" => false, "error" => "boom: bad command" }
        $stdout.write JSON.generate(resp) + "\\n"
      when "argv"
        resp = { "id" => msg["id"], "type" => "response", "command" => "argv",
                 "success" => true, "argv" => ARGV }
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

  describe "approve:" do
    # The stub server echoes ARGV — exactly the extra flags pi would
    # receive. The `--` keeps ruby from parsing them as interpreter options.
    def argv_for(**opts)
      c = described_class.new(bin: "ruby", args: ["-e", CLIENT_STUB_SERVER, "--"], **opts).start
      c.request("argv").value!(timeout: 2)["argv"]
    ensure
      c&.close
    end

    it "appends --approve when approve: true" do
      expect(argv_for(approve: true)).to eq(["--approve"])
    end

    it "appends --no-approve when approve: false" do
      expect(argv_for(approve: false)).to eq(["--no-approve"])
    end

    it "appends nothing by default" do
      expect(argv_for).to eq([])
    end
  end

  describe "transport death" do
    it "rejects in-flight requests promptly with TransportClosedError" do
      c = client
      future = c.request("die") # stub exits without responding
      expect { future.value!(timeout: 2) }
        .to raise_error(PiAgent::TransportClosedError, /exited with status 1/)
    ensure
      c&.close
    end

    it "exposes the death reason on the error" do
      c = client
      c.request("die").value!(timeout: 2)
      raise "expected TransportClosedError"
    rescue PiAgent::TransportClosedError => e
      expect(e.reason).to match(/exited with status 1/)
    ensure
      c&.close
    end

    it "fails fast on request and notify after the transport died" do
      c = client
      begin
        c.request("die").value!(timeout: 2)
      rescue PiAgent::TransportClosedError
        nil # the death we are arranging
      end

      expect { c.request("ping") }.to raise_error(PiAgent::TransportClosedError, /exited with status 1/)
      expect { c.notify("ping") }.to raise_error(PiAgent::TransportClosedError, /exited with status 1/)
    ensure
      c&.close
    end

    it "wakes subscribers with a synthetic transport_closed message" do
      c = client
      received = Queue.new
      c.subscribe { |msg| received << msg }
      c.request("die")

      msg = received.pop(timeout: 2)
      expect(msg["type"]).to eq(PiAgent::Client::TRANSPORT_CLOSED_TYPE)
      expect(msg["reason"]).to match(/exited with status 1/)
    ensure
      c&.close
    end

    it "replays the transport_closed message to a subscriber registered after death" do
      c = client
      begin
        c.request("die").value!(timeout: 2)
      rescue PiAgent::TransportClosedError
        nil # the death we are arranging
      end

      received = Queue.new
      c.subscribe { |msg| received << msg }

      msg = received.pop(timeout: 1)
      expect(msg["type"]).to eq(PiAgent::Client::TRANSPORT_CLOSED_TYPE)
      expect(msg["reason"]).to match(/exited with status 1/)
      expect(received.pop(timeout: 0.3)).to be_nil # replayed exactly once
    ensure
      c&.close
    end

    it "raises TransportClosedError when death races the write, rejecting the future" do
      # Deterministic mid-write death: the fake transport reports its own
      # death from inside write, then fails the write like a broken pipe.
      build_fake = lambda do
        Class.new do
          attr_accessor :on_close

          def start = self

          def write(_obj)
            on_close.call("death during write")
            raise PiAgent::ProtocolError, "Broken pipe writing to subprocess"
          end

          def close(**) = nil
          def alive? = false
        end.new
      end
      factory_for = lambda do |fake|
        lambda do |on_close:, **|
          fake.on_close = on_close
          fake
        end
      end

      c = described_class.new(transport_factory: factory_for.call(build_fake.call)).start
      expect { c.request("ping") }
        .to raise_error(PiAgent::TransportClosedError, /death during write/)

      c2 = described_class.new(transport_factory: factory_for.call(build_fake.call)).start
      expect { c2.notify("ping") }
        .to raise_error(PiAgent::TransportClosedError, /death during write/)
    end

    it "raises TransportClosedError when the write error beats the death notification" do
      # The reverse ordering: the pipe breaks immediately, but the
      # transport reports the death only later (as the subprocess
      # transport's stdout drain window can make it do). The client must
      # wait out that lag instead of surfacing the raw pipe error.
      build_fake = lambda do
        Class.new do
          def start = self
          def write(_obj) = raise(PiAgent::ProtocolError, "Broken pipe writing to subprocess")
          def close(**) = nil
          def alive? = false
        end.new
      end
      new_client = lambda do
        captured = nil
        c = described_class.new(transport_factory: lambda { |on_close:, **|
          captured = on_close
          build_fake.call
        }).start
        [c, captured]
      end
      lagged_death = lambda do |on_close|
        Thread.new do
          sleep 0.3
          on_close.call("process terminated by signal 9")
        end
      end

      c, on_close = new_client.call
      notifier = lagged_death.call(on_close)
      expect { c.request("ping") }
        .to raise_error(PiAgent::TransportClosedError, /terminated by signal 9/)
      notifier.join

      c2, on_close2 = new_client.call
      notifier2 = lagged_death.call(on_close2)
      expect { c2.notify("ping") }
        .to raise_error(PiAgent::TransportClosedError, /terminated by signal 9/)
      notifier2.join
    end

    it "surfaces raw write errors immediately for old-shape factories" do
      # A factory never handed on_close can never signal death, so the
      # write-failure grace wait must be bypassed entirely — pre-0.3.0
      # behavior, and no added latency for old-shape transports.
      fake = Class.new do
        def start = self
        def write(_obj) = raise(PiAgent::ProtocolError, "Broken pipe writing to subprocess")
        def close(**) = nil
        def alive? = true
      end.new
      handlers = nil
      factory = lambda do |on_message:, on_stderr:|
        handlers = [on_message, on_stderr]
        fake
      end

      c = described_class.new(transport_factory: factory).start
      expect(handlers.size).to eq(2)

      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      expect { c.request("ping") }.to raise_error(PiAgent::ProtocolError, /Broken pipe/) do |e|
        expect(e).not_to be_a(PiAgent::TransportClosedError)
      end
      expect { c.notify("ping") }.to raise_error(PiAgent::ProtocolError, /Broken pipe/)
      elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started

      expect(elapsed).to be < 0.5 # far below DEATH_NOTIFICATION_GRACE
    end

    it "continues fanout to later subscribers when an earlier one raises" do
      c = client
      received = Queue.new
      c.subscribe { |_msg| raise "logging subscriber bug" }
      c.subscribe { |msg| received << msg }
      c.notify("broadcast")

      expect(received.pop(timeout: 2)).to eq({ "type" => "agent_start" })
      expect(received.pop(timeout: 2)).to eq({ "type" => "agent_end" })
    ensure
      c&.close
    end

    it "delivers the death notification past a raising subscriber" do
      c = client
      received = Queue.new
      c.subscribe { |_msg| raise "logging subscriber bug" }
      c.subscribe { |msg| received << msg if msg["type"] == PiAgent::Client::TRANSPORT_CLOSED_TYPE }
      c.request("die")

      expect(received.pop(timeout: 2)).not_to be_nil
    ensure
      c&.close
    end

    it "does not emit transport_closed to subscribers on a clean close" do
      c = client
      received = Queue.new
      c.subscribe { |msg| received << msg }
      c.close # joins the transport's reader threads before returning

      expect(received.pop(timeout: 0.3)).to be_nil
    end

    it "tolerates duplicate on_close notifications, keeping the first reason" do
      fake_transport = Class.new do
        def start = self
        def write(_obj) = nil
        def close(**) = nil
        def alive? = false
      end.new
      captured = nil
      c = described_class.new(transport_factory: lambda { |on_close:, **|
        captured = on_close
        fake_transport
      }).start

      future = c.request("ping")
      received = Queue.new
      c.subscribe { |msg| received << msg }
      captured.call("first death")
      captured.call("second death")

      expect { future.value!(timeout: 1) }
        .to raise_error(PiAgent::TransportClosedError, /first death/)
      expect(received.pop(timeout: 1)["reason"]).to eq("first death")
      expect(received.pop(timeout: 0.3)).to be_nil
    end
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

    describe "on_close factory compatibility" do
      it "does not pass on_close to an old-shape (on_message:, on_stderr:) factory" do
        # An old-shape lambda is strict about keywords: if the client passed
        # on_close:, this call would raise ArgumentError. It working end to
        # end proves the keyword is withheld.
        factory = lambda do |on_message:, on_stderr:|
          PiAgent::Transport::Subprocess.new(
            command: ["ruby", "-e", CLIENT_STUB_SERVER],
            on_message: on_message, on_stderr: on_stderr
          )
        end

        c = described_class.new(transport_factory: factory).start
        expect(c.request("ping").value!(timeout: 2)["success"]).to be true
      ensure
        c&.close
      end

      it "passes on_close to a factory declaring the keyword" do
        captured = :not_passed
        factory = lambda do |on_message:, on_stderr:, on_close: nil|
          captured = on_close
          PiAgent::Transport::Subprocess.new(
            command: ["ruby", "-e", CLIENT_STUB_SERVER],
            on_message: on_message, on_stderr: on_stderr, on_close: on_close
          )
        end

        c = described_class.new(transport_factory: factory).start
        expect(captured).to respond_to(:call)
      ensure
        c&.close
      end

      it "passes on_close to a factory accepting **kwargs" do
        captured = {}
        factory = lambda do |on_message:, **rest|
          captured = rest
          PiAgent::Transport::Subprocess.new(
            command: ["ruby", "-e", CLIENT_STUB_SERVER],
            on_message: on_message, **rest
          )
        end

        c = described_class.new(transport_factory: factory).start
        expect(captured.keys).to include(:on_close)
      ensure
        c&.close
      end

      it "inspects non-proc callables via their call method" do
        script = CLIENT_STUB_SERVER
        factory_class = Class.new do
          define_method(:call) do |on_message:, on_stderr:|
            PiAgent::Transport::Subprocess.new(
              command: ["ruby", "-e", script],
              on_message: on_message, on_stderr: on_stderr
            )
          end
        end

        c = described_class.new(transport_factory: factory_class.new).start
        expect(c.request("ping").value!(timeout: 2)["success"]).to be true
      ensure
        c&.close
      end

      it "ignores an unrelated #parameters method on a callable factory" do
        script = CLIENT_STUB_SERVER
        factory_class = Class.new do
          # An app-domain method that happens to be named `parameters`;
          # introspection must go through #call, not this.
          def parameters = nil

          define_method(:call) do |on_message:, on_stderr:|
            PiAgent::Transport::Subprocess.new(
              command: ["ruby", "-e", script],
              on_message: on_message, on_stderr: on_stderr
            )
          end
        end

        c = described_class.new(transport_factory: factory_class.new).start
        expect(c.request("ping").value!(timeout: 2)["success"]).to be true
      ensure
        c&.close
      end
    end
  end
end
