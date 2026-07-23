# frozen_string_literal: true

module PiAgent
  # Thin typed wrapper over a pi RPC event message. The native JSON payload
  # is preserved on `#raw` so callers can reach fields we haven't given a
  # dedicated accessor yet.
  #
  # Event types are exposed as Ruby symbols (e.g. `:text_delta`,
  # `:agent_settled`) matching the upstream protocol's `type` field.
  class Event
    # Event types that terminate a single prompt's event stream.
    # `agent_end` only finishes one low-level run; retries, compaction, or
    # queued continuations may follow. `agent_settled` is emitted once all
    # automatic work has finished.
    TERMINAL_TYPES = %i[agent_settled].freeze

    attr_reader :raw, :type

    def initialize(raw)
      @raw = raw
      @type = raw["type"]&.to_sym
    end

    def terminal?
      TERMINAL_TYPES.include?(@type)
    end

    def [](key)
      @raw[key.to_s]
    end

    # Common shorthand for streaming text deltas.
    # `message_update` with `assistantMessageEvent.type == "text_delta"`.
    def delta
      assistant_event&.[]("delta")
    end

    # True for an `extension_error` event, or a `message_update` whose
    # assistant event is an error (agent turn errored or was aborted).
    def error?
      @type == :extension_error || assistant_event_type == :error
    end

    # Best-effort error text for an error event; nil if not an error.
    def error_message
      return @raw["error"] if @type == :extension_error
      return nil unless assistant_event_type == :error

      assistant_event["error"] || assistant_event["message"]
    end

    # Reason for an assistant-event error: "aborted" or "error". nil
    # otherwise. Use this to distinguish a user abort from a real failure.
    def error_reason
      return nil unless assistant_event_type == :error

      assistant_event["reason"]
    end

    def to_h
      @raw
    end

    def inspect
      "#<#{self.class.name} type=#{@type.inspect}>"
    end

    private

    def assistant_event
      ev = @raw["assistantMessageEvent"]
      ev.is_a?(Hash) ? ev : nil
    end

    def assistant_event_type
      assistant_event&.[]("type")&.to_sym
    end
  end
end
