# pi-agent-rb

Ruby client for the [pi coding agent](https://github.com/earendil-works/pi).
Spawns `pi --mode rpc` and speaks its JSONL protocol from Ruby. Designed for
building interactive agent UIs (web, TUI) on top of pi.

> Not officially maintained by the pi project.

## Requirements

- Ruby 3.2+
- `pi` on `PATH` (install via `npm i -g @earendil-works/pi-coding-agent`)
- This gem is pinned against pi `0.75.3`; other versions may work but are not verified.

## Quick start (planned API)

```ruby
require 'pi_agent'

PiAgent.open do |pi|
  session = pi.session_create(
    model: 'anthropic/claude-sonnet-4-5',
    system_prompt: 'You are a helpful assistant.'
  )

  session.prompt('Hello').stream do |event|
    case event.type
    when :text_delta            then print event.delta
    when :tool_execution_start  then puts "\n[tool: #{event.name}]"
    when :turn_end              then break
    end
  end
end
```

Not yet implemented — `PiAgent::Client` is currently a stub.

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
