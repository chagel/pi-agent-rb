# frozen_string_literal: true

module PiAgent
  class Error < StandardError; end

  class BinaryNotFoundError < Error; end
  class VersionMismatchError < Error; end
  class ProtocolError < Error; end
  class SessionError < Error; end
  class TimeoutError < Error; end

  # Raised when the transport dies out from under the client — child
  # process exit, read-stream EOF, fatal stream error — while requests or
  # event streams are outstanding, and on any `request`/`notify` attempted
  # after the death. A caller-initiated `Client#close` never raises it.
  # `#reason` carries the transport's short description of what happened
  # (e.g. "process terminated by signal 9").
  class TransportClosedError < ProtocolError
    attr_reader :reason

    def initialize(reason)
      @reason = reason
      super("Transport closed: #{reason}")
    end
  end

  # Raised when an RPC command returns `success: false`. Carries the
  # failing command name so callers can branch on it.
  class CommandError < Error
    attr_reader :command

    def initialize(message, command: nil)
      @command = command
      super(message)
    end
  end
end
