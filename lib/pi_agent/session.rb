# frozen_string_literal: true

module PiAgent
  # High-level agent session. Wraps a Client and exposes prompt-flow
  # ergonomics: submit a prompt and iterate the resulting event stream.
  #
  #   PiAgent.session do |session|
  #     session.prompt("Write a haiku").each do |event|
  #       print event.delta if event.type == :message_update
  #     end
  #   end
  #
  # A pi RPC process hosts exactly one session, so there is no
  # create/select step — the Session *is* the running pi process.
  #
  # v1 limitation: `prompt` streams one agent cycle (agent_start..agent_end).
  # Messages queued mid-flight via `follow_up`/`steer` run in subsequent
  # cycles; consume those by calling `prompt`-less `events` or another
  # `prompt`. Bidirectional extension UI is not yet surfaced here.
  class Session
    # Max time to wait for the next event before assuming the agent stalled.
    DEFAULT_EVENT_TIMEOUT = 300
    # Max time to wait for a command to be acknowledged.
    DEFAULT_ACK_TIMEOUT = 30

    attr_reader :client

    def initialize(client)
      @client = client
    end

    # Submit a user prompt. With a block, yields each Event until the
    # agent finishes (agent_end), then returns self. Without a block,
    # returns an Enumerator of Events.
    def prompt(message, images: nil, event_timeout: DEFAULT_EVENT_TIMEOUT, &block)
      params = { message: message }
      params[:images] = images if images
      stream = event_stream("prompt", params, event_timeout: event_timeout)

      return stream unless block

      stream.each(&block)
      self
    end

    # Queue a steering message while the agent is running. Delivered after
    # the current assistant turn finishes its tool calls, before the next
    # LLM call. Fire-and-forget; raises on rejection.
    def steer(message, images: nil)
      params = { message: message }
      params[:images] = images if images
      @client.request("steer", params).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    # Queue a follow-up message, delivered only after the agent stops.
    def follow_up(message, images: nil)
      params = { message: message, streamingBehavior: "followUp" }
      params[:images] = images if images
      @client.request("prompt", params).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    # Abort the current agent run. Fire-and-forget.
    def abort
      @client.notify("abort")
      self
    end

    def set_model(model)
      @client.request("set_model", model: model).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    def set_thinking(level)
      @client.request("set_thinking", level: level).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    def get_state
      @client.request("get_state").value!(timeout: DEFAULT_ACK_TIMEOUT)
    end

    def close
      @client.close
    end

    private

    # Subscribe, send the command, then yield Events from the notification
    # stream until a terminal event. The subscription is scoped to one
    # iteration of the returned Enumerator so cleanup is deterministic.
    def event_stream(type, params, event_timeout:)
      Enumerator.new do |yielder|
        queue = Queue.new
        handle = @client.subscribe { |msg| queue << msg }
        begin
          @client.request(type, params).value!(timeout: DEFAULT_ACK_TIMEOUT)
          pump_events(queue, yielder, event_timeout)
        ensure
          @client.unsubscribe(handle)
        end
      end
    end

    def pump_events(queue, yielder, event_timeout)
      loop do
        msg = queue.pop(timeout: event_timeout)
        raise TimeoutError, "No event received within #{event_timeout}s" if msg.nil?

        event = Event.new(msg)
        yielder << event
        break if event.terminal?
      end
    end
  end
end
