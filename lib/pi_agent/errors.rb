# frozen_string_literal: true

module PiAgent
  class Error < StandardError; end

  class BinaryNotFoundError < Error; end
  class VersionMismatchError < Error; end
  class ProtocolError < Error; end
  class SessionError < Error; end
  class TimeoutError < Error; end

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
