# frozen_string_literal: true

module PiAgent
  class Error < StandardError; end

  class BinaryNotFoundError < Error; end
  class VersionMismatchError < Error; end
  class ProtocolError < Error; end
  class SessionError < Error; end
  class TimeoutError < Error; end
end
