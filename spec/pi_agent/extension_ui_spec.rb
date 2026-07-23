# frozen_string_literal: true

RSpec.describe PiAgent::ExtensionUI do
  # Captures messages the ExtensionUI writes back (extension_ui_response).
  def writer_double(queue)
    Object.new.tap do |obj|
      obj.define_singleton_method(:write) { |msg| queue << msg }
    end
  end

  def request(method, **fields)
    { "type" => "extension_ui_request", "id" => "ui-1", "method" => method.to_s }.merge(
      fields.transform_keys(&:to_s)
    )
  end

  describe PiAgent::ExtensionUI::Request do
    it "parses method as a symbol and exposes dialog fields" do
      req = described_class.new(request(:select, title: "Pick", options: %w[a b], timeout: 5000))
      expect(req.method).to eq(:select)
      expect(req.title).to eq("Pick")
      expect(req.options).to eq(%w[a b])
      expect(req.timeout_ms).to eq(5000)
      expect(req.dialog?).to be true
    end

    it "flags fire-and-forget methods as non-dialog" do
      expect(described_class.new(request(:notify)).dialog?).to be false
      expect(described_class.new(request(:set_editor_text)).dialog?).to be false
    end
  end

  describe "#dispatch" do
    it "answers a confirm dialog with the handler's boolean result" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(_req) { true })
      eui.dispatch(request(:confirm, title: "OK?"))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", confirmed: true }
      )
    end

    it "answers confirm with confirmed:false when the handler returns false" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(_req) { false })
      eui.dispatch(request(:confirm))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", confirmed: false }
      )
    end

    it "answers a select dialog with the handler's string value" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(req) { req.options.first })
      eui.dispatch(request(:select, options: %w[Allow Block]))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", value: "Allow" }
      )
    end

    it "answers an input dialog with the entered text" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(_req) { "typed value" })
      eui.dispatch(request(:input))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", value: "typed value" }
      )
    end

    it "cancels a dialog when the handler returns nil" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(_req) {})
      eui.dispatch(request(:input))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", cancelled: true }
      )
    end

    it "cancels a dialog when the handler raises" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(_req) { raise "boom" })
      eui.dispatch(request(:confirm))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", cancelled: true }
      )
    end

    it "auto-cancels dialogs when no handler is configured" do
      writes = Queue.new
      eui = described_class.new(writer: writer_double(writes))
      eui.dispatch(request(:select, options: %w[a b]))

      expect(writes.pop(timeout: 2)).to eq(
        { type: "extension_ui_response", id: "ui-1", cancelled: true }
      )
    end

    it "invokes the handler for fire-and-forget methods but writes nothing" do
      writes = Queue.new
      seen = Queue.new
      eui = described_class.new(writer: writer_double(writes), handler: ->(req) { seen << req.method })
      eui.dispatch(request(:notify, message: "hi", notifyType: "warning"))

      expect(seen.pop(timeout: 2)).to eq(:notify)
      expect(writes.pop(timeout: 0.3)).to be_nil
    end
  end

  describe "session integration" do
    # Stub pi: on prompt, asks a confirm dialog, waits for the response on a
    # later stdin line, then echoes the answer and ends.
    ROUNDTRIP_STUB = <<~RUBY
      require "json"
      $stdout.sync = true
      def emit(obj) = $stdout.write(JSON.generate(obj) + "\\n")

      $stdin.each_line do |line|
        msg = JSON.parse(line)
        case msg["type"]
        when "prompt"
          emit({ "id" => msg["id"], "type" => "response", "command" => "prompt", "success" => true })
          emit({ "type" => "agent_start" })
          emit({ "type" => "extension_ui_request", "id" => "ui-1", "method" => "confirm", "title" => "Proceed?" })
        when "extension_ui_response"
          emit({ "type" => "message_update",
                 "assistantMessageEvent" => { "type" => "text_delta", "delta" => "answer=\#{msg["confirmed"]}" } })
          emit({ "type" => "agent_end", "messages" => [] })
          emit({ "type" => "agent_settled" })
        end
      end
    RUBY

    it "answers a dialog mid-prompt without leaking the request into the event stream" do
      handler = ->(req) { req.method == :confirm }
      client = PiAgent::Client.new(bin: "ruby", args: ["-e", ROUNDTRIP_STUB], extension_ui: handler)
      session = PiAgent::Session.new(client.start)

      events = session.prompt("go").to_a
      expect(events.map(&:type)).not_to include(:extension_ui_request)
      expect(events.filter_map(&:delta)).to include("answer=true")
    ensure
      session&.close
    end

    it "auto-cancels the dialog when the session has no handler" do
      client = PiAgent::Client.new(bin: "ruby", args: ["-e", ROUNDTRIP_STUB])
      session = PiAgent::Session.new(client.start)

      deltas = session.prompt("go").filter_map(&:delta)
      # confirm cancelled => extension sees false => stub echoes nil for "confirmed"
      expect(deltas).to include("answer=")
    ensure
      session&.close
    end
  end
end
