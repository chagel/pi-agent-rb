# pi-agent-rb

Ruby client for the [pi coding agent](https://github.com/earendil-works/pi).
Spawns `pi --mode rpc` and speaks its JSONL protocol from Ruby. Designed for
building interactive agent UIs (web, TUI) on top of pi.

> Not officially maintained by the pi project.

## Requirements

- Ruby 3.2+
- `pi` on `PATH` (install via `npm i -g @earendil-works/pi-coding-agent`)
- This gem is pinned against pi `0.75.3`; other versions may work but are not verified.

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

Other session methods: `steer`, `follow_up`, `abort`, `set_model`,
`set_thinking`, `get_state`.

For low-level RPC access (raw `request`/`notify`/`subscribe`), use
`PiAgent.open`, which yields a `PiAgent::Client`.

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
