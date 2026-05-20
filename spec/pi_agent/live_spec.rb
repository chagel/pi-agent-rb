# frozen_string_literal: true

# Integration tests against a real `pi --mode rpc` process.
# Gated behind PI_LIVE_TEST=1 because they require the pi binary installed.
# These do not make LLM calls — they exercise transport + protocol only.
RSpec.describe "live pi --mode rpc", :live do
  before do
    skip "set PI_LIVE_TEST=1 to run live pi integration tests" unless ENV["PI_LIVE_TEST"] == "1"
  end

  it "spawns pi, completes a get_commands round trip, and shuts down" do
    client = PiAgent.open(args: ["--mode", "rpc", "--no-session"])
    response = client.request("get_commands").value!(timeout: 15)

    expect(response["type"]).to eq("response")
    expect(response["success"]).to be true
  ensure
    client&.close
  end

  it "reports the pi binary version matches the supported pin" do
    bin = PiAgent::Client.resolve_bin
    # pi writes its version to stderr, not stdout.
    version = `#{bin} --version 2>&1`.strip
    warn "pi version #{version} (gem pinned to #{PiAgent::SUPPORTED_PI_VERSION})" \
      unless version == PiAgent::SUPPORTED_PI_VERSION
    expect(version).to match(/\A\d+\.\d+\.\d+/)
  end
end
