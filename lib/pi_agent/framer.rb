# frozen_string_literal: true

module PiAgent
  # Strict LF-only line framer for the pi RPC protocol.
  #
  # The protocol explicitly forbids generic line readers (Ruby `readline`,
  # Node `readline`) because they also split on U+2028 / U+2029, which are
  # valid inside JSON strings.
  #
  # Feed bytes; yield complete lines with any trailing CR stripped. Empty
  # lines are dropped (the protocol uses single LFs between records).
  class Framer
    LF = "\n"

    def initialize
      @buffer = String.new(encoding: Encoding::BINARY)
    end

    def feed(bytes)
      @buffer << bytes.b
      while (idx = @buffer.index(LF))
        line = @buffer.byteslice(0, idx)
        @buffer = @buffer.byteslice(idx + 1, @buffer.bytesize - idx - 1) || String.new(encoding: Encoding::BINARY)
        line.chomp!("\r")
        next if line.empty?

        yield line.force_encoding(Encoding::UTF_8)
      end
    end

    def buffered?
      !@buffer.empty?
    end
  end
end
