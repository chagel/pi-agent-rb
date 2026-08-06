# pi-agent-rb

[![CI](https://github.com/chagel/pi-agent-rb/actions/workflows/ci.yml/badge.svg)](https://github.com/chagel/pi-agent-rb/actions/workflows/ci.yml)
[![Gem Version](https://img.shields.io/gem/v/pi-agent-rb.svg)](https://rubygems.org/gems/pi-agent-rb)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Ruby client for the [pi coding agent](https://github.com/earendil-works/pi).
Spawns `pi --mode rpc` and speaks its JSONL protocol from Ruby. Designed for
building interactive agent UIs (web, TUI) on top of pi.

> Not officially maintained by the pi project.

## Requirements

- Ruby 3.3+
- `pi` 0.80.4+ on `PATH` (install via `npm i -g @earendil-works/pi-coding-agent`)
- This gem is pinned against pi `0.84.0`; other versions may work but are not verified.

## Installation

Install the gem:

```bash
gem install pi-agent-rb
```

Or add it to your `Gemfile`:

```ruby
gem "pi-agent-rb"
```

then run `bundle install`.

## Quick start

```ruby
require "pi_agent"

PiAgent.session do |session|
  session.prompt("Write a haiku about Ruby") do |event|
    print event.delta if event.type == :message_update
  end
end
```

A pi RPC process hosts one session, so there is no create/select step —
`PiAgent.session` spawns `pi --mode rpc` and the session *is* that process.

`prompt` yields each [`Event`](lib/pi_agent/event.rb) until the agent fully
finishes (`agent_settled`). Unlike `agent_end`, this includes any automatic
retry, compaction retry, or queued continuation. Without a block it returns
an `Enumerator`:

```ruby
PiAgent.session do |session|
  events = session.prompt("List three primes")
  text = events.filter_map(&:delta).join
  puts text
end
```

For a single-shot call, `run` submits a prompt, drains the stream, and
returns the final assistant text — pi's print mode:

```ruby
PiAgent.session do |session|
  puts session.run("What's 2 + 2?")   # => "4"
end
```

Other session methods:

- Prompting: `steer`, `follow_up`, `events`, `abort`
- Model: `set_model`, `cycle_model`, `available_models`, `set_thinking`, `available_thinking_levels`
- State: `get_state`, `messages`, `last_assistant_text`, `session_stats`
- Context: `compact`
- Sessions: `new_session`, `switch_session`, `fork`, `clone_session`,
  `set_session_name`

`set_model` accepts either `set_model("anthropic/claude-sonnet-4-5")` or
`set_model("anthropic", "claude-sonnet-4-5")`.

A `prompt` streams the complete session-level run
(`agent_start`..`agent_settled`). Pass a block to `follow_up` for a sequential
follow-up that starts immediately when idle (or queues when an agent is
already running) and drains each `Event` through `agent_settled`:

```ruby
PiAgent.session do |session|
  session.prompt("Draft a haiku") { |e| print e.delta if e.type == :message_update }
  session.follow_up("Now translate it to French") { |e| print e.delta if e.type == :message_update }
end
```

The block form is race-free: `follow_up` subscribes to the event stream before
sending a `prompt` with pi's `streamingBehavior: "followUp"`, so none of the
cycle's events are missed. Use it only after the previous high-level stream has
settled; pi events have no run IDs, so a session permits only one high-level
event stream at a time. While a stream is active, use blockless `follow_up` to
queue a continuation—the active stream will include it through
`agent_settled`. The block form accepts plain agent input, not slash commands.

Pi emits `agent_end` after each low-level agent run, but may then retry,
compact and retry, or process queued continuations. It emits
`agent_settled` only when no automatic work remains, so high-level streams
use that as their completion boundary. Upstream added the RPC event in pi
0.80.4; it is available in this gem's pinned pi 0.84.0.

`events` is a lower-level, prompt-less drain of the same stream. Because it
subscribes lazily when iteration begins, it only works when you subscribe
*before* the cycle starts — e.g. begin iterating it from a thread, then
trigger the cycle. For the common follow-up case, prefer the block form
above. `prompt`, block-form `follow_up`, and `events` are single-flight on a
session; starting another before the current stream settles raises
`PiAgent::SessionError` rather than consuming an unrelated settlement event.

### Images

`prompt`, `steer`, and `follow_up` accept an `images:` array. Entries
may be `PiAgent::Image` objects, file path strings, or raw
`ImageContent` hashes, mixed freely:

```ruby
PiAgent.session do |session|
  session.prompt("What's in these?", images: [
    "screenshot.png",                                  # path
    PiAgent::Image.from_file("diagram.jpg"),           # Image object
    PiAgent::Image.from_bytes(blob, mime_type: "image/webp")
  ]) { |e| ... }
end
```

Supported formats: png, jpeg, gif, webp.

For low-level RPC access (raw `request`/`notify`/`subscribe`), use
`PiAgent.open`, which yields a `PiAgent::Client`.

## Project trust

Since pi `0.79.0`, project-local inputs (`.pi/settings.json`, project
extensions, resources, and packages) are trust-gated. In RPC mode pi never
prompts: unless the project was already trusted (e.g. interactively on the
same machine), it **silently ignores them**. Pass `approve: true` to trust
the project, or `approve: false` to explicitly ignore project inputs:

```ruby
PiAgent.session(cwd: "/path/to/project", approve: true) do |session|
  # project .pi extensions and settings are loaded
end
```

## Extension UI

pi extensions can request user interaction (confirm, select, input,
editor) mid-run. Pass an `extension_ui` handler to answer them:

```ruby
handler = lambda do |req|
  case req.method
  when :confirm then true              # confirmed
  when :select  then req.options.first # pick an option
  when :input   then "default"         # entered text
  when :editor  then req.prefill       # edited text
  # fire-and-forget (:notify, :set_status, ...) — return value ignored
  end
end

PiAgent.session(extension_ui: handler) do |session|
  session.prompt("Refactor the parser") { |e| ... }
end
```

Returning `nil` from a dialog handler cancels it. With no handler,
dialogs are auto-cancelled so the agent never hangs. Handlers run on
their own thread and never block the event stream.

If a handler raises, the dialog is cancelled as a fail-safe. Use
`on_extension_ui_error` when the application needs to observe those failures:

```ruby
on_ui_error = lambda do |error, request|
  logger.error(
    "Extension UI handler failed",
    error: error.class.name,
    request_id: request.id,
    method: request.method
  )
end

PiAgent.session(
  extension_ui: handler,
  on_extension_ui_error: on_ui_error
) do |session|
  session.prompt("Refactor the parser") { |e| ... }
end
```

The observer runs on the same worker thread and cannot change the fail-safe
cancellation. If it raises, the dialog is still cancelled. Requests can contain
sensitive titles, messages, options, or prefilled text, so avoid logging
`request.raw` without application-specific filtering.

## Forking

```ruby
PiAgent.session do |session|
  session.prompt("Add a feature") { |e| ... }

  # Branch from an earlier message
  forkable = session.fork_messages           # [{ "entryId" =>, "text" => }]
  session.fork(forkable.first["entryId"])    # => { "text" =>, "cancelled" => }

  session.clone_session                      # duplicate the active branch
  session.set_session_name("feature-work")
end
```

`fork`/`clone_session` return `cancelled: true` (rather than raising) if
a pi extension vetoes the operation — that is an expected outcome, not
an error.

## Custom transports

By default the client spawns `pi --mode rpc` as a local subprocess. Pass
`transport_factory:` to run pi somewhere else — a container, a remote
sandbox:

```ruby
factory = lambda do |on_message:, on_stderr:, on_close:|
  MySandboxTransport.new(
    sandbox: sandbox,
    on_message: on_message, on_stderr: on_stderr, on_close: on_close
  )
end

PiAgent.session(transport_factory: factory) do |session|
  # pi runs inside the sandbox; the protocol flows through your transport
end
```

The factory receives the client's handlers and returns an object
implementing `#start`, `#write(Hash)`, `#close(timeout:)`, and `#alive?`.
[`Transport`](lib/pi_agent/transport.rb) documents the full contract;
[`Transport::Subprocess`](lib/pi_agent/transport/subprocess.rb) is the
reference implementation.

`on_close:` is the transport's death notification. Invoke it exactly
once, with a short human-readable reason (e.g.
`"process terminated by signal 9"`), when the transport reaches a
terminal state *on its own* — process exit, read-stream EOF, fatal stream
error — and only after delivering any stdout messages already read. Do
not invoke it for a shutdown initiated through `#close`. When it fires,
the client fails in-flight requests and live event streams promptly with
`PiAgent::TransportClosedError` (reason on `#reason`) instead of letting
them wait out the 30s ack / 300s event timeouts, and later
`request`/`notify` calls fail fast with the same error. Subscribers that
register after the death get the notification replayed once, so an event
stream started late still ends promptly.

`on_close:` is optional and backward compatible: the client inspects the
factory's parameters and passes the keyword only when the factory accepts
it (explicitly or via `**kwargs`). An existing
`(on_message:, on_stderr:)` factory keeps working unchanged — the
timeouts then remain the only backstop when pi dies.

## Errors

- A failed RPC command (`success: false`) raises `PiAgent::CommandError`,
  which carries the failing `#command` name.
- If the transport dies out from under the client (pi OOM-killed, sandbox
  torn down), in-flight requests and event streams raise
  `PiAgent::TransportClosedError` promptly, with the death reason on
  `#reason`. A caller-initiated `close` never raises it. This requires
  the transport to report death — the bundled subprocess transport does;
  for custom transports see [Custom transports](#custom-transports).
- Agent-side errors arrive *in* the event stream, not as exceptions —
  inspect them with `Event#error?`, `#error_message`, and `#error_reason`
  (`"aborted"` vs `"error"`). This covers `extension_error` events and
  errored assistant turns. The gem does not abort your iteration on
  agent errors; you decide how to react.

## Protocol reference

The wire protocol is documented upstream in
[`packages/coding-agent/docs/rpc.md`](https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/rpc.md).

## Development

```bash
bin/setup        # bundle install
bundle exec rspec
```

## License

MIT
