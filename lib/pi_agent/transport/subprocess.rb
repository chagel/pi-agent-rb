# frozen_string_literal: true

require "open3"
require "json"

module PiAgent
  module Transport
    # Runs `pi --mode rpc` as a local child process and speaks NDJSON
    # over its stdio.
    #
    # One reader thread per pipe; stdout lines are JSON-parsed and
    # dispatched to `on_message`; stderr lines are forwarded raw to
    # `on_stderr`. Writes are serialized through a mutex so concurrent
    # senders don't interleave JSON payloads on stdin.
    class Subprocess
      DEFAULT_CHUNK_SIZE = 4096
      DEFAULT_CLOSE_TIMEOUT = 5
      # How long to let the stdout reader drain buffered output after the
      # child exits before reporting the death (or closing) anyway — a
      # descendant that inherited the pipe can hold it open indefinitely.
      EXIT_DRAIN_TIMEOUT = 1

      attr_reader :pid

      # `cwd` sets the child's working directory — pi's built-in tools
      # (bash/read/edit/...) operate relative to it. nil leaves the
      # child in this process's working directory.
      #
      # `on_close`, when given, is invoked exactly once with a short
      # human-readable reason when the child reaches a terminal state on
      # its own — exit, stdout EOF, fatal stream error. A caller-initiated
      # #close is not reported. The notification fires after the remaining
      # stdout has been dispatched, so responses that raced the death are
      # not lost. Child exit is observed independently of the stdout pipe:
      # if a descendant inherited the pipe and holds it open past the
      # child's death, the notification still fires after a bounded drain
      # window (EXIT_DRAIN_TIMEOUT) instead of waiting for EOF.
      def initialize(command:, env: {}, cwd: nil, on_message: nil, on_stderr: nil, on_close: nil)
        @command = Array(command)
        @env = env.transform_keys(&:to_s)
        @cwd = cwd
        @on_message = on_message
        @on_stderr = on_stderr
        @on_close = on_close
        @write_mutex = Mutex.new
        @owner_closed = false
        @close_notified = false
        @close_notified_mutex = Mutex.new
      end

      def start
        @stdin, @stdout, @stderr, @wait_thr = Open3.popen3(*spawn_args)
        @pid = @wait_thr.pid
        @stdin.binmode
        @stdout.binmode
        @stderr.binmode
        @stdout_thread = Thread.new { read_loop(@stdout, :stdout) }
        @stderr_thread = Thread.new { read_loop(@stderr, :stderr) }
        @exit_watch_thread = Thread.new { watch_exit }
        self
      end

      def write(obj)
        payload = "#{JSON.generate(obj)}\n"
        @write_mutex.synchronize do
          raise ProtocolError, "Transport closed" if @owner_closed

          @stdin.write(payload)
          @stdin.flush
        end
      rescue Errno::EPIPE
        raise ProtocolError, "Broken pipe writing to subprocess (process may have exited)"
      end

      def close(timeout: DEFAULT_CLOSE_TIMEOUT)
        return if mark_owner_closed!

        safe_close(@stdin)
        wait_for_exit(timeout)
        readers = [@stdout_thread, @stderr_thread].compact
        # Bounded drain: a descendant that inherited a pipe can hold it
        # open past the child's exit; force the readers out by closing
        # the pipes after the window rather than hanging the close.
        readers.each { |t| t.join(EXIT_DRAIN_TIMEOUT) }
        safe_close(@stdout)
        safe_close(@stderr)
        (readers + [@exit_watch_thread]).compact.each(&:join)
      end

      def alive?
        !!@wait_thr&.alive?
      end

      def exit_status
        @wait_thr&.value
      end

      private

      def spawn_args
        args = [@env, *@command]
        args << { chdir: @cwd.to_s } if @cwd
        args
      end

      # Marks that the owner requested shutdown via #close (as opposed to
      # the child dying on its own). Returns whether it was already set.
      def mark_owner_closed!
        @write_mutex.synchronize do
          return true if @owner_closed

          @owner_closed = true
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
      rescue StandardError => e
        fatal = e
      ensure
        # Stdout EOF and fatal stream errors are terminal even if the child
        # is somehow still running; by this point everything read has been
        # dispatched. (Child exit itself is watched independently — see
        # watch_exit — since a descendant holding the pipe can defer EOF.)
        notify_close(fatal_error: fatal) if channel == :stdout
      end

      # Watches the child process itself, so its death is reported even
      # when the stdout pipe stays open (a descendant that inherited the
      # write end). Gives the stdout reader a bounded window to drain
      # buffered output first, so responses that raced the exit are
      # dispatched before the notification.
      def watch_exit
        status = @wait_thr.value
        return if owner_closed?

        @stdout_thread&.join(EXIT_DRAIN_TIMEOUT)
        notify_close(status: status)
      end

      def dispatch_stdout(line)
        msg = JSON.parse(line)
        @on_message&.call(msg)
      rescue JSON::ParserError => e
        @on_stderr&.call("[pi-agent-rb] invalid JSON on stdout: #{e.message}: #{line.inspect}")
      end

      # Death notification: fire on_close exactly once. Owner-initiated
      # #close marks @owner_closed before teardown, so the resulting EOF
      # and exit are expected and stay silent.
      def notify_close(fatal_error: nil, status: nil)
        return if @on_close.nil? || owner_closed?

        already = @close_notified_mutex.synchronize do
          was = @close_notified
          @close_notified = true
          was
        end
        return if already

        @on_close.call(close_reason(fatal_error, status))
      end

      def owner_closed?
        @write_mutex.synchronize { @owner_closed }
      end

      def close_reason(fatal_error, status)
        return "fatal stream error: #{fatal_error.class}: #{fatal_error.message}" if fatal_error

        status ||= reap_exit_status
        if status.nil?
          "stdout reached EOF (process still running)"
        elsif status.signaled?
          "process terminated by signal #{status.termsig}"
        else
          "process exited with status #{status.exitstatus}"
        end
      end

      # The child normally exits right around stdout EOF; give it a moment
      # to be reaped so the reason can carry the real exit status.
      def reap_exit_status
        @wait_thr&.join(1)&.value
      rescue StandardError
        nil
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
end
