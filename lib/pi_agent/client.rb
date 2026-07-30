# frozen_string_literal: true

module PiAgent
  # High-level client. Owns a Transport, correlates request/response by id,
  # and fans notifications out to subscribers.
  #
  #   client = PiAgent::Client.new.start
  #   client.subscribe { |msg| ... }              # all server-pushed messages
  #   future = client.request("get_commands")     # request/response
  #   future.value!(timeout: 5)                   # blocks for response
  #   client.notify("set_thinking", level: "off") # fire-and-forget (no id)
  #   client.close
  #
  # By default the client spawns `pi --mode rpc` as a local subprocess.
  # Pass `transport_factory:` — a callable `(on_message:, on_stderr:) ->
  # transport` — to run pi somewhere else (e.g. inside a remote sandbox).
  # See Transport for the transport contract.
  #
  # Since pi 0.79.0 project-local inputs (.pi/settings.json, project
  # extensions, resources, packages) are trust-gated, and in RPC mode pi
  # silently ignores them unless the project was already trusted. Pass
  # `approve: true` to trust the project (`--approve`), or `approve: false`
  # to explicitly ignore project inputs (`--no-approve`).
  class Client
    DEFAULT_BIN = "pi"
    DEFAULT_ARGS = ["--mode", "rpc"].freeze

    attr_reader :bin

    def self.resolve_bin(override = nil)
      candidate = override || ENV["PI_BIN"] || DEFAULT_BIN
      path = which(candidate)
      return path if path

      raise BinaryNotFoundError, <<~MSG
        Could not find the `pi` binary on PATH (looked for #{candidate.inspect}).

        Install with: npm install -g @earendil-works/pi-coding-agent@#{PiAgent::SUPPORTED_PI_VERSION}
        Or set PI_BIN to an explicit path.
      MSG
    end

    def self.which(cmd)
      exts = ENV["PATHEXT"] ? ENV["PATHEXT"].split(";") : [""]
      ENV["PATH"].to_s.split(File::PATH_SEPARATOR).each do |dir|
        exts.each do |ext|
          candidate = File.join(dir, "#{cmd}#{ext}")
          return candidate if File.executable?(candidate) && !File.directory?(candidate)
        end
      end
      nil
    end

    def initialize(bin: nil, args: DEFAULT_ARGS, env: {}, cwd: nil, approve: nil,
                   extension_ui: nil, on_extension_ui_error: nil, transport_factory: nil)
      @extension_ui_handler = extension_ui
      @extension_ui_error_handler = on_extension_ui_error
      args = [*args, approve ? "--approve" : "--no-approve"] unless approve.nil?
      @transport_factory = transport_factory || build_subprocess_factory(bin, args, env, cwd)
      @pending = {}
      @pending_mutex = Mutex.new
      @next_id = 0
      @subscribers = []
      @subscribers_mutex = Mutex.new
      @transport = nil
      @extension_ui = nil
    end

    def start
      @transport = @transport_factory.call(
        on_message: method(:handle_message),
        on_stderr: method(:handle_stderr)
      )
      @extension_ui = ExtensionUI.new(
        writer: @transport,
        handler: @extension_ui_handler,
        on_error: @extension_ui_error_handler
      )
      @transport.start
      self
    end

    def request(type, params = {})
      id = next_id
      future = Future.new
      @pending_mutex.synchronize { @pending[id] = future }
      payload = { id: id, type: type }.merge(params)
      @transport.write(payload)
      future
    end

    def notify(type, params = {})
      payload = { type: type }.merge(params)
      @transport.write(payload)
    end

    def subscribe(&block)
      raise ArgumentError, "subscribe requires a block" unless block

      @subscribers_mutex.synchronize { @subscribers << block }
      block
    end

    def unsubscribe(handle)
      @subscribers_mutex.synchronize { @subscribers.delete(handle) }
    end

    def close
      # Drain extension UI handler threads while the transport is still
      # open so their responses can still be written.
      @extension_ui&.shutdown
      @transport&.close
      reject_pending(ProtocolError.new("Transport closed before response"))
    end

    def alive?
      @transport&.alive? || false
    end

    private

    # Default factory: resolve the pi binary now (so a missing binary
    # fails fast at construction) and build a subprocess transport on
    # start, once Client's message handlers are known.
    def build_subprocess_factory(bin, args, env, cwd)
      @bin = self.class.resolve_bin(bin)
      command = [@bin, *Array(args)]
      lambda do |on_message:, on_stderr:|
        Transport::Subprocess.new(
          command: command, env: env, cwd: cwd,
          on_message: on_message, on_stderr: on_stderr
        )
      end
    end

    def next_id
      @pending_mutex.synchronize do
        @next_id += 1
        "req-#{@next_id}"
      end
    end

    def handle_message(msg)
      type = msg["type"]
      if type == "response" && msg["id"]
        deliver_response(msg)
      elsif type == "extension_ui_request"
        @extension_ui&.dispatch(msg)
      else
        notify_subscribers(msg)
      end
    end

    def deliver_response(msg)
      future = @pending_mutex.synchronize { @pending.delete(msg["id"]) }
      return unless future

      if msg["success"] == false
        future.reject(CommandError.new(msg["error"] || "command failed: #{msg.inspect}", command: msg["command"]))
      else
        future.resolve(msg)
      end
    end

    def notify_subscribers(msg)
      callbacks = @subscribers_mutex.synchronize { @subscribers.dup }
      callbacks.each { |cb| cb.call(msg) }
    end

    def handle_stderr(line)
      # no-op by default; future versions may wire a logger
    end

    def reject_pending(error)
      pending = @pending_mutex.synchronize do
        snapshot = @pending.values
        @pending.clear
        snapshot
      end
      pending.each { |f| f.reject(error) }
    end
  end
end
