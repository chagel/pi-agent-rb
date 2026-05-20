# frozen_string_literal: true

RSpec.describe PiAgent::Event do
  it "exposes the type as a symbol" do
    event = described_class.new({ "type" => "text_delta" })
    expect(event.type).to eq(:text_delta)
  end

  it "preserves the raw payload" do
    raw = { "type" => "turn_start", "turn" => 2 }
    expect(described_class.new(raw).raw).to eq(raw)
  end

  it "reads fields with string or symbol keys via #[]" do
    event = described_class.new({ "type" => "turn_start", "turn" => 3 })
    expect(event[:turn]).to eq(3)
    expect(event["turn"]).to eq(3)
  end

  it "flags agent_end as terminal" do
    expect(described_class.new({ "type" => "agent_end" }).terminal?).to be true
  end

  it "does not flag turn_end or message_end as terminal" do
    expect(described_class.new({ "type" => "turn_end" }).terminal?).to be false
    expect(described_class.new({ "type" => "message_end" }).terminal?).to be false
  end

  it "extracts a text delta from a message_update event" do
    event = described_class.new(
      {
        "type" => "message_update",
        "assistantMessageEvent" => { "type" => "text_delta", "delta" => "hello" }
      }
    )
    expect(event.delta).to eq("hello")
  end

  it "returns nil delta for events without an assistantMessageEvent" do
    expect(described_class.new({ "type" => "turn_start" }).delta).to be_nil
  end
end
