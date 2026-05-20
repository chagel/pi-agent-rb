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
    #
    # `images` accepts PiAgent::Image objects, file path strings, or
    # raw ImageContent hashes — in any mix.
    def prompt(message, images: nil, event_timeout: DEFAULT_EVENT_TIMEOUT, &block)
      stream = event_stream("prompt", message_params(message, images), event_timeout: event_timeout)

      return stream unless block

      stream.each(&block)
      self
    end

    # Queue a steering message while the agent is running. Delivered after
    # the current assistant turn finishes its tool calls, before the next
    # LLM call. Fire-and-forget; raises on rejection.
    def steer(message, images: nil)
      @client.request("steer", message_params(message, images)).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    # Queue a follow-up message, delivered only after the agent stops.
    def follow_up(message, images: nil)
      @client.request("follow_up", message_params(message, images)).value!(timeout: DEFAULT_ACK_TIMEOUT)
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

    # Token usage, cost, and context-window stats for the current session.
    # Returns the data hash, including "sessionId" and "sessionFile".
    def session_stats
      request_data("get_session_stats")
    end

    # List user messages available for forking. Returns an array of
    # { "entryId" => ..., "text" => ... } hashes.
    def fork_messages
      request_data("get_fork_messages").fetch("messages", [])
    end

    # Fork a new branch from a previous user message (an entryId from
    # `fork_messages`). Returns { "text" => <forked-from text>,
    # "cancelled" => bool }; `cancelled` is true if an extension vetoed it.
    def fork(entry_id)
      request_data("fork", entryId: entry_id)
    end

    # Duplicate the current active branch into a new session at the
    # current position. Returns { "cancelled" => bool }. Maps to the
    # `clone` RPC command (named `clone_session` to avoid shadowing
    # Object#clone).
    def clone_session
      request_data("clone")
    end

    def set_session_name(name)
      @client.request("set_session_name", name: name).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    def close
      @client.close
    end

    private

    # Build the { message:, images? } params for a prompt-style command.
    def message_params(message, images)
      params = { message: message }
      normalized = normalize_images(images)
      params[:images] = normalized unless normalized.empty?
      params
    end

    # Coerce mixed image inputs into ImageContent hashes.
    def normalize_images(images)
      Array(images).map do |image|
        case image
        when Image  then image.to_h
        when String then Image.from_file(image).to_h
        when Hash   then image
        else raise ArgumentError, "Unsupported image: #{image.inspect}"
        end
      end
    end

    # Send a request and return its `data` payload (the part RPC commands
    # like fork/clone/get_fork_messages carry their result in).
    def request_data(type, params = {})
      response = @client.request(type, params).value!(timeout: DEFAULT_ACK_TIMEOUT)
      response["data"] || {}
    end

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
