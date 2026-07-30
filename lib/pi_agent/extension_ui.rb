# frozen_string_literal: true

module PiAgent
  # Handles the bidirectional Extension UI sub-protocol.
  #
  # pi extensions can request user interaction (`ctx.ui.select`,
  # `ctx.ui.confirm`, ...). In RPC mode these arrive as
  # `extension_ui_request` messages. Dialog methods block the agent until
  # the client sends a matching `extension_ui_response`; fire-and-forget
  # methods expect no response.
  #
  # Each request is handled on its own thread so a slow or blocking
  # handler never stalls the transport reader thread (and therefore the
  # agent event stream).
  #
  # The handler is a callable taking a Request and returning:
  #   - select / input / editor : a String value, or nil to cancel
  #   - confirm                 : true / false, or nil to cancel
  #   - fire-and-forget methods : return value ignored
  #
  # With no handler, dialogs are auto-cancelled so the agent never hangs.
  # Handler failures also cancel the dialog; pass `on_error` to observe them.
  class ExtensionUI
    DIALOG_METHODS = %i[select confirm input editor].freeze

    # One extension UI request. Wraps the raw protocol message.
    class Request
      attr_reader :id, :method, :raw

      def initialize(raw)
        @raw = raw
        @id = raw["id"]
        @method = raw["method"]&.to_sym
      end

      def dialog?
        DIALOG_METHODS.include?(@method)
      end

      def title = @raw["title"]
      def message = @raw["message"]
      def options = @raw["options"]
      def placeholder = @raw["placeholder"]
      def prefill = @raw["prefill"]
      def timeout_ms = @raw["timeout"]
      def notify_type = @raw["notifyType"]
      def text = @raw["text"]

      def [](key)
        @raw[key.to_s]
      end
    end

    def initialize(writer:, handler: nil, on_error: nil)
      @writer = writer
      @handler = handler
      @on_error = on_error
      @threads = []
      @mutex = Mutex.new
    end

    # Route an `extension_ui_request` message. Non-blocking: spawns a
    # thread to run the handler and (for dialogs) send the response.
    def dispatch(msg)
      request = Request.new(msg)
      @mutex.synchronize do
        @threads.select!(&:alive?)
        @threads << Thread.new { handle(request) }
      end
    end

    # Wait for in-flight handler threads to finish (each up to `timeout`s).
    def shutdown(timeout: 5)
      @mutex.synchronize { @threads.dup }.each { |t| t.join(timeout) }
    end

    private

    def handle(request)
      result = invoke_handler(request)
      return unless request.dialog?

      @writer.write(response_for(request, result))
    rescue ProtocolError
      # Transport closed during shutdown; the response is moot.
    end

    def invoke_handler(request)
      return nil if @handler.nil?

      @handler.call(request)
    rescue StandardError => e
      # A raising handler cancels the dialog rather than hanging the agent.
      notify_error(e, request)
      nil
    end

    def notify_error(error, request)
      @on_error&.call(error, request)
    rescue StandardError
      # Error observers cannot prevent the fail-closed response.
      nil
    end

    def response_for(request, result)
      base = { type: "extension_ui_response", id: request.id }
      return base.merge(cancelled: true) if result.nil?
      return base.merge(confirmed: result ? true : false) if request.method == :confirm

      base.merge(value: result.to_s)
    end
  end
end
