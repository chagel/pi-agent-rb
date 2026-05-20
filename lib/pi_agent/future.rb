# frozen_string_literal: true

require "monitor"

module PiAgent
  # Thread-safe single-shot promise. Used to correlate RPC requests with
  # their responses across the transport's stdout reader thread and the
  # caller's thread.
  class Future
    def initialize
      @mon = Monitor.new
      @cond = @mon.new_cond
      @resolved = false
      @value = nil
      @error = nil
    end

    def resolve(value)
      @mon.synchronize do
        return if @resolved

        @value = value
        @resolved = true
        @cond.broadcast
      end
    end

    def reject(error)
      raise ArgumentError, "error must be an Exception" unless error.is_a?(Exception)

      @mon.synchronize do
        return if @resolved

        @error = error
        @resolved = true
        @cond.broadcast
      end
    end

    def value!(timeout: nil)
      @mon.synchronize do
        unless @resolved
          @cond.wait(timeout)
          raise PiAgent::TimeoutError, "Future timed out after #{timeout}s" unless @resolved
        end
        raise @error if @error

        @value
      end
    end

    def resolved?
      @mon.synchronize { @resolved }
    end
  end
end
