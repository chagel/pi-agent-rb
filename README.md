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
- `pi` on `PATH` (install via `npm i -g @earendil-works/pi-coding-agent`)
- This gem is pinned against pi `0.80.3`; other versions may work but are not verified.

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

`prompt` yields each [`Event`](lib/pi_agent/event.rb) until the agent
finishes (`agent_end`). Without a block it returns an `Enumerator`:

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
- Model: `set_model`, `cycle_model`, `available_models`, `set_thinking`
- State: `get_state`, `messages`, `last_assistant_text`, `session_stats`
- Context: `compact`
- Sessions: `new_session`, `switch_session`, `fork`, `clone_session`,
  `set_session_name`

`set_model` accepts either `set_model("anthropic/claude-sonnet-4-5")` or
`set_model("anthropic", "claude-sonnet-4-5")`.

A `prompt` streams one agent cycle (`agent_start`..`agent_end`). A message
queued with `follow_up` runs in a *later* cycle; pass a block to `follow_up`
to drain that cycle. Like `prompt`, it yields each `Event` until `agent_end`:

```ruby
PiAgent.session do |session|
  session.prompt("Draft a haiku") { |e| print e.delta if e.type == :message_update }
  session.follow_up("Now translate it to French") { |e| print e.delta if e.type == :message_update }
end
```

The block form is race-free: `follow_up` subscribes to the event stream
*before* sending the message, so none of the cycle's events are missed.

`events` is a lower-level, prompt-less drain of the same stream. Because it
subscribes lazily when iteration begins, it only works when you subscribe
*before* the cycle starts — e.g. begin iterating it from a thread, then
trigger the cycle. For the common follow-up case, prefer the block form
above.

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

## Errors

- A failed RPC command (`success: false`) raises `PiAgent::CommandError`,
  which carries the failing `#command` name.
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
