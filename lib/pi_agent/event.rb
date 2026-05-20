# frozen_string_literal: true

module PiAgent
  # Thin typed wrapper over a pi RPC event message. The native JSON payload
  # is preserved on `#raw` so callers can reach fields we haven't given a
  # dedicated accessor yet.
  #
  # Event types are exposed as Ruby symbols (e.g. `:text_delta`,
  # `:agent_end`) matching the upstream protocol's `type` field.
  class Event
    # Event types that terminate a single prompt's event stream.
    # `agent_end` fires when the agent finishes processing the current
    # prompt cycle; we stop iterating then.
    TERMINAL_TYPES = %i[agent_end].freeze

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
      ev = @raw["assistantMessageEvent"]
      return nil unless ev.is_a?(Hash)

      ev["delta"]
    end

    def to_h
      @raw
    end

    def inspect
      "#<#{self.class.name} type=#{@type.inspect}>"
    end
  end
end
