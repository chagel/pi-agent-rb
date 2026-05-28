# frozen_string_literal: true

require "tmpdir"

RSpec.describe PiAgent do
  it "has a version number" do
    expect(PiAgent::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "declares a supported upstream pi version" do
    expect(PiAgent::SUPPORTED_PI_VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe PiAgent::Client do
    it "resolves the pi binary on PATH" do
      Dir.mktmpdir do |dir|
        fake = File.join(dir, "pi")
        File.write(fake, "#!/bin/sh\n")
        File.chmod(0o755, fake)

        with_path(dir) do
          expect(PiAgent::Client.resolve_bin).to eq(fake)
        end
      end
    end

    it "raises BinaryNotFoundError when the binary is missing" do
      expect { PiAgent::Client.resolve_bin("definitely-not-pi-xyz") }
        .to raise_error(PiAgent::BinaryNotFoundError, /Could not find/)
    end

    def with_path(dir)
      original = ENV.fetch("PATH", nil)
      ENV["PATH"] = "#{dir}#{File::PATH_SEPARATOR}#{original}"
      yield
    ensure
      ENV["PATH"] = original
    end
  end
end
