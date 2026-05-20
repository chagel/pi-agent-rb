# frozen_string_literal: true

require "open3"
require "json"

module PiAgent
  # Spawns a subprocess and speaks NDJSON over its stdio.
  #
  # One reader thread per pipe; stdout lines are JSON-parsed and dispatched
  # to `on_message`; stderr lines are forwarded raw to `on_stderr`.
  # Writes are serialized through a mutex so concurrent senders don't
  # interleave JSON payloads on stdin.
  class Transport
    DEFAULT_CHUNK_SIZE = 4096
    DEFAULT_CLOSE_TIMEOUT = 5

    attr_reader :pid

    def initialize(command:, env: {}, on_message: nil, on_stderr: nil)
      @command = Array(command)
      @env = env.transform_keys(&:to_s)
      @on_message = on_message
      @on_stderr = on_stderr
      @write_mutex = Mutex.new
      @closed = false
    end

    def start
      @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(@env, *@command)
      @pid = @wait_thr.pid
      @stdin.binmode
      @stdout.binmode
      @stderr.binmode
      @stdout_thread = Thread.new { read_loop(@stdout, :stdout) }
      @stderr_thread = Thread.new { read_loop(@stderr, :stderr) }
      self
    end

    def write(obj)
      payload = "#{JSON.generate(obj)}\n"
      @write_mutex.synchronize do
        raise ProtocolError, "Transport closed" if @closed

        @stdin.write(payload)
        @stdin.flush
      end
    rescue Errno::EPIPE
      raise ProtocolError, "Broken pipe writing to subprocess (process may have exited)"
    end

    def close(timeout: DEFAULT_CLOSE_TIMEOUT)
      return if mark_closed!

      safe_close(@stdin)
      wait_for_exit(timeout)
      [@stdout_thread, @stderr_thread].compact.each(&:join)
      safe_close(@stdout)
      safe_close(@stderr)
    end

    def alive?
      !!@wait_thr&.alive?
    end

    def exit_status
      @wait_thr&.value
    end

    private

    def mark_closed!
      @write_mutex.synchronize do
        return true if @closed

        @closed = true
        false
      end
    end

    def safe_close(io)
      io&.close
    rescue IOError
      # already closed
    end

    def wait_for_exit(timeout)
      return if @wait_thr&.join(timeout)

      terminate_process
      return if @wait_thr&.join(2)

      kill_process
      @wait_thr&.join
    end

    def read_loop(io, channel)
      framer = Framer.new
      loop do
        chunk = io.readpartial(DEFAULT_CHUNK_SIZE)
        framer.feed(chunk) do |line|
          channel == :stdout ? dispatch_stdout(line) : @on_stderr&.call(line)
        end
      end
    rescue IOError, Errno::EBADF
      # Pipe closed; reader exits normally. (EOFError descends from IOError.)
    end

    def dispatch_stdout(line)
      msg = JSON.parse(line)
      @on_message&.call(msg)
    rescue JSON::ParserError => e
      @on_stderr&.call("[pi-agent-rb] invalid JSON on stdout: #{e.message}: #{line.inspect}")
    end

    def terminate_process
      Process.kill("TERM", @pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Process already gone
    end

    def kill_process
      Process.kill("KILL", @pid)
    rescue Errno::ESRCH, Errno::EPERM
      # Process already gone
    end
  end
end
