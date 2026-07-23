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

  it "flags agent_settled as terminal" do
    expect(described_class.new({ "type" => "agent_settled" }).terminal?).to be true
  end

  it "does not flag agent_end, turn_end, or message_end as terminal" do
    expect(described_class.new({ "type" => "agent_end" }).terminal?).to be false
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

  describe "error inspection" do
    it "flags an extension_error event and exposes its message" do
      event = described_class.new(
        {
          "type" => "extension_error",
          "extensionPath" => "/x/ext.ts",
          "event" => "tool_call",
          "error" => "extension blew up"
        }
      )
      expect(event.error?).to be true
      expect(event.error_message).to eq("extension blew up")
    end

    it "flags a message_update whose assistant event is an error" do
      event = described_class.new(
        {
          "type" => "message_update",
          "assistantMessageEvent" => { "type" => "error", "reason" => "error", "error" => "model failed" }
        }
      )
      expect(event.error?).to be true
      expect(event.error_message).to eq("model failed")
      expect(event.error_reason).to eq("error")
    end

    it "distinguishes an abort from a real error via error_reason" do
      event = described_class.new(
        {
          "type" => "message_update",
          "assistantMessageEvent" => { "type" => "error", "reason" => "aborted" }
        }
      )
      expect(event.error?).to be true
      expect(event.error_reason).to eq("aborted")
    end

    it "reports non-error events as not errors" do
      event = described_class.new(
        {
          "type" => "message_update",
          "assistantMessageEvent" => { "type" => "text_delta", "delta" => "hi" }
        }
      )
      expect(event.error?).to be false
      expect(event.error_message).to be_nil
      expect(event.error_reason).to be_nil
    end
  end
end
