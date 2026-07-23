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
  # A message queued with `follow_up` runs in a later cycle; pass a block to
  # `follow_up` to drain that cycle race-free (it subscribes before sending).
  # `events` is a prompt-less drain of the same stream for when you have
  # already subscribed before the cycle starts. Bidirectional extension UI
  # is not yet surfaced here.
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

    # Drain the event stream without submitting a new prompt. With a block,
    # yields each Event until the cycle finishes (agent_end) and returns
    # self; without a block, returns an Enumerator of Events.
    #
    # The subscription is established lazily, when iteration begins — so any
    # cycle triggered *before* you call `events` may have already emitted
    # events that are then missed. To drain a `follow_up` cycle race-free,
    # pass a block to `follow_up` instead. Use `events` only when you
    # subscribe before the cycle starts (e.g. from a thread that begins
    # iterating, then trigger the cycle). With nothing queued, it blocks
    # for `event_timeout` (300s default).
    def events(event_timeout: DEFAULT_EVENT_TIMEOUT, &block)
      stream = subscribed_stream(event_timeout: event_timeout)

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
    #
    # Without a block this is fire-and-forget: it queues the message and
    # returns self. With a block it drains the resulting agent cycle
    # race-free — the subscription is established *before* the message is
    # sent, so no events are missed — yielding each Event until agent_end
    # and returning self. Prefer the block form to consume a follow-up;
    # the standalone `events` drain only works if you subscribe first.
    def follow_up(message, images: nil, event_timeout: DEFAULT_EVENT_TIMEOUT, &block)
      params = message_params(message, images)
      unless block
        @client.request("follow_up", params).value!(timeout: DEFAULT_ACK_TIMEOUT)
        return self
      end

      event_stream("follow_up", params, event_timeout: event_timeout).each(&block)
      self
    end

    # Single-shot helper mirroring pi's print mode: submit `message`,
    # drain the whole event stream, and return the final assistant text
    # (nil if the agent produced none). Yields each Event to an optional
    # block while the stream drains.
    def run(message, images: nil, event_timeout: DEFAULT_EVENT_TIMEOUT)
      prompt(message, images: images, event_timeout: event_timeout) do |event|
        yield event if block_given?
      end
      last_assistant_text
    end

    # Abort the current agent run. Fire-and-forget.
    def abort
      @client.notify("abort")
      self
    end

    # Switch to a specific model. Accepts either a single "provider/modelId"
    # string or the two parts as separate arguments.
    def set_model(provider, model_id = nil)
      provider, model_id = provider.split("/", 2) if model_id.nil?
      @client.request("set_model", provider: provider, modelId: model_id)
             .value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    # Switch to the next configured model. Returns the new
    # { "model" =>, "thinkingLevel" =>, "isScoped" => } hash, or {} when
    # only one model is available.
    def cycle_model
      request_data("cycle_model")
    end

    # All configured models, as an array of Model hashes.
    def available_models
      request_data("get_available_models").fetch("models", [])
    end

    # Set the reasoning level: "off", "minimal", "low", "medium", "high",
    # or "xhigh" (xhigh is OpenAI codex-max only).
    def set_thinking(level)
      @client.request("set_thinking_level", level: level).value!(timeout: DEFAULT_ACK_TIMEOUT)
      self
    end

    # Thinking levels supported by the current model, as an array of strings
    # (e.g. ["off", "low", "medium", "high"]). Returns ["off"] for a model
    # without reasoning support.
    def available_thinking_levels
      request_data("get_available_thinking_levels").fetch("levels", [])
    end

    def get_state
      @client.request("get_state").value!(timeout: DEFAULT_ACK_TIMEOUT)
    end

    # Full conversation history, as an array of AgentMessage hashes.
    def messages
      request_data("get_messages").fetch("messages", [])
    end

    # Text of the last assistant message, or nil if there is none.
    def last_assistant_text
      request_data("get_last_assistant_text")["text"]
    end

    # Manually compact the conversation context to reduce token usage.
    # Returns the result hash ({ "summary" =>, "firstKeptEntryId" =>,
    # "tokensBefore" => }).
    def compact(custom_instructions: nil)
      params = {}
      params[:customInstructions] = custom_instructions if custom_instructions
      request_data("compact", params)
    end

    # Start a fresh session in the same pi process. Pass `parent_session:`
    # (a session file path) to record provenance. Returns
    # { "cancelled" => bool }; cancelled is true if an extension vetoed it.
    def new_session(parent_session: nil)
      params = {}
      params[:parentSession] = parent_session if parent_session
      request_data("new_session", params)
    end

    # Load a different session file into this process. Returns
    # { "cancelled" => bool }; cancelled is true if an extension vetoed it.
    def switch_session(path)
      request_data("switch_session", sessionPath: path)
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

    # Session entries in append order (excluding the session header). Unlike
    # `messages`, this includes pre-compaction history and abandoned branches.
    # Entry ids are stable, so pass `since:` (the last entry id you have seen)
    # to get only entries strictly after it — a durable cursor across restarts.
    # Returns { "entries" => [...], "leafId" => <id or nil> }.
    def entries(since: nil)
      params = {}
      params[:since] = since if since
      request_data("get_entries", params)
    end

    # The session as a tree of entries. Each node is
    # { "entry" =>, "children" => [...], "label"? =>, "labelTimestamp"? => }.
    # Returns { "tree" => [...], "leafId" => <id or nil> }.
    def tree
      request_data("get_tree")
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
    # stream until a terminal event.
    def event_stream(type, params, event_timeout:)
      subscribed_stream(event_timeout: event_timeout) do
        @client.request(type, params).value!(timeout: DEFAULT_ACK_TIMEOUT)
      end
    end

    # Subscribe, run `before_pump` (e.g. send a command) once the
    # subscription is live so no events are missed in the gap, then yield
    # Events until a terminal event. The subscription is scoped to one
    # iteration of the returned Enumerator so cleanup is deterministic.
    def subscribed_stream(event_timeout:, &before_pump)
      Enumerator.new do |yielder|
        queue = Queue.new
        handle = @client.subscribe { |msg| queue << msg }
        begin
          before_pump&.call
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
