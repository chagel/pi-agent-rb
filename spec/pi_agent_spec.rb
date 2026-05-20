# frozen_string_literal: true

RSpec.describe PiAgent do
  it "has a version number" do
    expect(PiAgent::VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  it "declares a supported upstream pi version" do
    expect(PiAgent::SUPPORTED_PI_VERSION).to match(/\A\d+\.\d+\.\d+/)
  end

  describe PiAgent::Client do
    it "resolves the pi binary on PATH" do
      expect(PiAgent::Client.resolve_bin).to match(%r{/pi$})
    end

    it "raises BinaryNotFoundError when the binary is missing" do
      expect { PiAgent::Client.resolve_bin("definitely-not-pi-xyz") }
        .to raise_error(PiAgent::BinaryNotFoundError, /Could not find/)
    end
  end
end
