# frozen_string_literal: true

module PiAgent
  # Spawns `pi --mode rpc` and speaks its JSONL protocol.
  #
  # This is a scaffold. Real implementation lands in M1/M2:
  #   - Open3.popen3 spawn with strict LF framing
  #   - Request/response correlation via id field
  #   - Notification dispatch to subscribers
  #   - Session lifecycle (create, prompt, steer, follow_up, abort, fork)
  #   - Extension UI round-trips
  class Client
    DEFAULT_BIN = "pi"

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

    def initialize(bin: nil)
      @bin = self.class.resolve_bin(bin)
    end

    def close
      # Will terminate the spawned pi process once implemented.
    end
  end
end
