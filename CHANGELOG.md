# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.17] - 2026-07-17

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.10` (from
  `0.80.9`). Upstream is a Kimi Coding maintenance patch: K3 now uses
  adaptive thinking correctly (exposing its supported max level and
  replaying empty-signature thinking blocks), inherited Kimi Coding
  requests use Anthropic adaptive thinking effort without token budgets,
  and inherited Kimi K3 pricing/thinking-level metadata plus catalog
  generation for xAI models are fixed. All of these are provider/model
  metadata concerns; no new RPC commands were added and the JSONL RPC
  surface this gem drives is unchanged — this is a pin bump only.

## [0.1.16] - 2026-07-16

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.9` (from
  `0.80.8`). Upstream adds Kimi K3 support across built-in providers (Kimi
  Coding, Moonshot AI, Moonshot AI China, OpenRouter, Vercel AI Gateway)
  with deferred tool loading for extension-driven tool activation, switches
  xAI login to a prefilled device-authorization flow with Grok 4.5 as the
  default model, and removes older Grok variants from the built-in xAI
  catalog. All of these are provider/extension concerns; no new RPC
  commands were added and the JSONL RPC surface this gem drives is
  unchanged — this is a pin bump only.

## [0.1.15] - 2026-07-16

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.8` (from
  `0.80.7`). This release unifies model runtime and provider authentication:
  a new `ModelRuntime` centralizes model configuration, provider-owned
  `/login`, and dynamic provider catalogs; `/model` now refreshes configured
  providers in the background (with `pi update --models` to force an
  immediate catalog refresh); and xAI gains device-code OAuth login with
  Grok 4.5 Responses support (low/medium/high thinking). Several SDK/
  extension-facing breaking changes ship with it — the SDK's
  `CreateAgentSessionOptions.authStorage`/`modelRegistry` options are
  replaced by the async `modelRuntime` option, `AuthStorage` is no longer
  exported, redundant `ModelRuntime` projections and
  `ModelRegistry.getApiKeyAndHeaders()` are removed in favor of pi-ai
  `Models` methods and `ModelRuntime.getAuth()`, and extension-facing
  `ModelRegistry.refresh()` is now async. These are all SDK/extension
  concerns and do not affect the RPC command surface this gem drives. No
  new RPC commands were added, so the client API is unchanged — this is a
  pin bump only.

## [0.1.14] - 2026-07-15

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.7` (from
  `0.80.6`). This is a CLI/SDK/library maintenance batch: cache-friendly
  dynamic tool loading for extension tools (preserving prompt-cache
  prefixes on supported Anthropic and OpenAI Responses models), a `Ctrl+X`
  shortcut to copy the last/selected assistant message, native `xhigh` and
  `max` thinking levels for Claude Fable 5 across generated provider
  catalogs, inherited `toolChoice` support for OpenAI/Codex Responses, plus
  numerous provider/streaming fixes (OpenRouter context windows and session
  IDs, Bedrock auth, Cloudflare Workers AI credentials, Azure OpenAI
  reasoning replay) and removal of the system prompt's current date to fix
  cross-date cache invalidation. One SDK-level breaking change: the
  `openai-responses` `compat.sendSessionIdHeader` flag in `models.json` was
  removed in favor of `compat.sessionAffinityFormat`; this does not affect
  the RPC command surface this gem drives. No new RPC commands were added,
  so the client API is unchanged — this is a pin bump only.

## [0.1.13] - 2026-07-10

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.6` (from
  `0.80.5`). This is a CLI/SDK/library maintenance batch: an opt-in `max`
  thinking level (above `xhigh`, exposed across CLI, SDK, RPC model
  selection, and themes), request-wide input-token pricing tiers for
  long-context cost accounting, `~` home-directory expansion for the
  `shellPath` setting, plus fixes to post-compaction output-token
  budgeting, GPT-5.4/5.5/5.6 long-context cost/metadata, and Anthropic
  thinking-block preservation. No new RPC commands were added to the
  protocol surface this gem drives, so the client API is unchanged — this
  is a pin bump only.

## [0.1.12] - 2026-07-09

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.5` (from
  `0.80.3`). This range is a library/SDK and provider maintenance batch:
  Claude Sonnet 5 on Copilot and Bedrock prompt caching, GPT-5.6 metadata,
  refreshed model catalogs, bash-timeout validation, extension hooks
  (`before_provider_headers`, `InlineExtension`), session storage exports
  (`InMemorySessionStorage`, `JsonlSessionStorage`), custom jsonl session
  header metadata, and numerous provider/streaming fixes. No new RPC
  commands were added to the protocol surface this gem drives, so the
  client API is unchanged — this is a pin bump only.

## [0.1.11] - 2026-06-30

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.3`. This release
  adds two RPC commands to the protocol surface (`get_entries`, `get_tree`),
  a package `./rpc-entry` export for launching pi directly in RPC mode, and
  a raft of SDK/library-level changes (Claude Sonnet 5 support, `gpt-5.5` as
  the default OpenAI model, provider/streaming fixes). The existing RPC
  commands this gem drives are unchanged.

### Added
- `Session#entries(since:)` wraps the new `get_entries` RPC command: session
  entries in append order, including pre-compaction history and abandoned
  branches. Pass `since:` (a stable entry id) as a durable cursor to fetch
  only entries after it. Returns `{ "entries" => [...], "leafId" => ... }`.
- `Session#tree` wraps the new `get_tree` RPC command: the session as a tree
  of entries. Returns `{ "tree" => [...], "leafId" => ... }`.

## [0.1.10] - 2026-06-25

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.80.2` (rolls up
  0.80.0–0.80.2: the old global `@earendil-works/pi-ai` API moved to the
  `@earendil-works/pi-ai/compat` entrypoint and the selective `/base`
  provider entrypoints were removed; plus provider/auth resolution fixes
  (Bedrock, Cloudflare, Fireworks, OpenAI Responses/Codex), session-name
  newline normalization, and a `Ctrl+J` newline keybinding). These are
  SDK/library-level changes; no changes to the RPC protocol surface or the
  `--approve`/`--no-approve` flags this gem drives.

### Added
- `Session#follow_up` now accepts a block to drain the agent cycle the queued
  message triggers, mirroring `prompt`'s block contract. It is race-free —
  the event subscription is established before the message is sent, so none
  of the cycle's events are missed.
- `Session#events`: a lower-level, prompt-less drain of the agent event
  stream, for callers that subscribe before the cycle starts (e.g. from a
  thread). Mirrors `prompt`'s block/Enumerator contract. (The class docstring
  already referenced this method; it now exists.)

## [0.1.9] - 2026-06-22

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.10` (extension
  compaction events now carry `reason`/`willRetry` metadata, a safer
  `pi update` flow that installs the exact checked version, a `find` tool
  fix for nested git repository boundaries, and assorted streaming/docs
  fixes). Features/fixes only; no changes to the RPC protocol surface or the
  `--approve`/`--no-approve` flags this gem drives.

## [0.1.8] - 2026-06-20

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.9` (rolls up
  0.79.7–0.79.9: automatic light/dark theme mode, selective provider base
  entry points, Mistral prompt caching, chat-template thinking for
  OpenAI-compatible providers, and assorted provider/streaming/edit fixes).
  RPC-adjacent changes are additive only: compact results and compaction
  events now carry estimated post-compaction token counts, and RPC
  unknown-command errors now include the request id. No changes to the RPC
  protocol surface or the `--approve`/`--no-approve` flags this gem drives.

## [0.1.7] - 2026-06-16

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.6` (rolls up
  0.79.5–0.79.6: provider-scoped API key `env` overrides in `auth.json`, a
  global `httpProxy` setting, HTTP dispatcher respecting caller-provided
  `fetch` overrides, and assorted provider/streaming fixes; no changes to the
  RPC protocol surface or the `--approve`/`--no-approve` flags this gem
  drives).

## [0.1.6] - 2026-06-15

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.4` (rolls up
  0.79.2–0.79.4: automatic light/dark theme detection, Bash tool output
  truncation fixes, corrected OpenAI/Codex context-window metadata, project
  trust detection no longer reading global state from `$HOME`, and assorted
  fixes; no changes to the RPC protocol surface or the `--approve`/`--no-approve`
  flags this gem drives).

## [0.1.5] - 2026-06-09

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.1` (adds Claude
  Fable 5 model support, a global `defaultProjectTrust` setting to configure
  unresolved-trust behavior, prompt template argument defaults, extension
  autocomplete trigger characters, and assorted fixes; no changes to the RPC
  protocol surface or the `--approve`/`--no-approve` flags this gem drives).

## [0.1.4] - 2026-06-09

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.79.0` (cache-hit
  visibility in footer, richer SDK exports, and assorted fixes; the RPC wire
  protocol this gem drives is unchanged).
- **Behavior change in pi 0.79.0:** project-local inputs (`.pi/settings.json`,
  project extensions, resources, packages) are now trust-gated. In RPC mode pi
  does not prompt — without a saved trust decision it silently ignores them.
  Pass the new `approve: true` option to keep loading them (see Added).

### Added
- `approve:` option on `Client.new` / `PiAgent.session` / `PiAgent.open`:
  `true` appends `--approve` to the pi spawn args (trust the project),
  `false` appends `--no-approve` (explicitly ignore project inputs); the
  default `nil` leaves pi's own behavior untouched.

## [0.1.3] - 2026-05-29

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.77.0` (adds Claude
  Opus 4.8 metadata, `--exclude-tools`, and Codex subscription device login;
  no changes to the RPC protocol surface this gem drives).

## [0.1.2] - 2026-05-27

### Changed
- Minimum Ruby raised to `3.3.0` (Ruby 3.2 reached EOL 2026-04-01).

### Added
- GitHub Actions CI: rspec across Ruby 3.3, 3.4, 4.0, head; rubocop on 4.0.
- README badges (CI status, Gem version, License) and installation section.

## [0.1.1] - 2026-05-27

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.76.0`.

## [0.1.0] - 2026-05-27

### Added
- Initial project scaffold.
- `Session#run` single-shot helper (pi print-mode equivalent).
- `Session` commands: `cycle_model`, `available_models`, `messages`,
  `last_assistant_text`, `compact`, `new_session`, `switch_session`.

### Fixed
- `Session#set_model` now sends `provider`/`modelId` (pi rejected the
  previous single `model` field).
- `Session#set_thinking` now sends the `set_thinking_level` command (pi
  has no `set_thinking` command).
