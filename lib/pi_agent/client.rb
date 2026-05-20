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

    def initialize(bin: nil, args: DEFAULT_ARGS, env: {})
      @bin = self.class.resolve_bin(bin)
      @args = Array(args)
      @env = env
      @pending = {}
      @pending_mutex = Mutex.new
      @next_id = 0
      @subscribers = []
      @subscribers_mutex = Mutex.new
      @transport = nil
    end

    def start
      @transport = Transport.new(
        command: [@bin, *@args],
        env: @env,
        on_message: method(:handle_message),
        on_stderr: method(:handle_stderr)
      ).start
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
      @transport&.close
      reject_pending(ProtocolError.new("Transport closed before response"))
    end

    def alive?
      @transport&.alive? || false
    end

    private

    def next_id
      @pending_mutex.synchronize do
        @next_id += 1
        "req-#{@next_id}"
      end
    end

    def handle_message(msg)
      if msg["type"] == "response" && msg["id"]
        deliver_response(msg)
      else
        notify_subscribers(msg)
      end
    end

    def deliver_response(msg)
      future = @pending_mutex.synchronize { @pending.delete(msg["id"]) }
      return unless future

      if msg["success"] == false
        future.reject(ProtocolError.new(msg["error"] || "command failed: #{msg.inspect}"))
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
