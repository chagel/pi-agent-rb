# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.85.1` (from
  `0.84.4`, folding in `0.85.0`). These are CLI/TUI/provider/SDK
  feature-and-fix batches; none of the changes alter the JSONL RPC
  command/response shapes this gem drives, so no gem API change is required.
  - v0.85.1 adds GPT-6 Astra via OpenAI API keys / Codex subscriptions and
    faster Alt-held fullscreen mouse-wheel scrolling — provider and TUI
    concerns outside the RPC surface.
  - v0.85.1 fixes SDK import failures caused by 0.85.0 unintentionally
    publishing internal experimental code (upstream #9132); the experimental
    client/plugin subpaths are now source-only. Upstream explicitly notes the
    supported local SDK and stdio RPC API are unchanged, so this gem's
    subprocess/JSONL transport is unaffected.
  - v0.85.1 also fixes configurable save keybindings in the model/thinking
    selectors, mouse-hover selection/recenter behavior, and long prompt-cache
    requests for GPT-5.6+ Responses models — all TUI/provider concerns
    outside the RPC stream this gem consumes.
  - v0.85.0 adds persistent Claude thinking effort across supported
    Anthropic transports, fullscreen transcript controls ("jump to latest
    message"), and restorable in-memory sessions via
    `SessionManager.inMemory()`. These are CLI/TUI/provider or TypeScript
    SDK concerns, outside the JSONL RPC surface this Ruby client speaks.
  - v0.85.0 restores the `@earendil-works/pi-coding-agent/client`
    compatibility entry point (a TypeScript library import path), which
    does not affect this gem's subprocess/JSONL transport.
  - v0.85.0 fixes RPC abort reporting success without cancelling an
    in-progress manual compaction (upstream #8920). This is a behavioral
    fix to abort handling, not a change to the command/response shapes the
    gem's `Framer` parses, so existing behavior is compatible.
  - v0.85.0 fixes the built-in `bash`, `edit`, `find`, `grep`, `ls`,
    `read`, and `write` tools ignoring `ctx.cwd` (upstream #8627) and the
    `write` tool reporting UTF-16 code-unit counts as byte counts (#8979).
    These are pi-side tool-execution fixes; the tools run inside pi and
    their RPC event shapes are unchanged, so the gem is unaffected.
  - Remaining v0.85.0 changes (provider stream/adapter fixes, model
    catalog updates, managed fd/ripgrep download fixes, session-file and
    session-share fixes) are CLI/TUI/provider or persistence concerns
    outside the RPC stream this gem consumes.

## [0.3.2] - 2026-09-03

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.84.4` (from
  `0.84.3`). This is a CLI/TUI/provider/extension feature-and-fix batch;
  none of the changes alter the JSONL RPC command/response shapes this gem
  drives, so no gem API change is required.
  - v0.84.4 adds terminal capability overrides, `ui_prompt_start` /
    `ui_prompt_end` extension events, fullscreen selection-copy controls,
    and the experimental DeepSeek V4 Flash Vision model. These are
    CLI/TUI/provider or TypeScript extension-API concerns, outside the
    JSONL RPC surface this Ruby client speaks.
  - v0.84.4 adds a new `clear_queue` RPC command to retrieve and remove
    queued steering and follow-up messages (upstream #8432). This gem
    drives the queue via `Session#steer` / `Session#follow_up` but does not
    yet wrap `clear_queue`; the addition is purely additive and optional,
    so existing behavior is unaffected. Exposing a `clear_queue` helper is
    a possible future enhancement, not required for this bump.
  - v0.84.4 fixes resumed sessions corrupting the next appended entry when
    their JSONL file lacks a trailing newline (upstream #8345). This is a
    pi-side session-file persistence fix, not part of the RPC stream this
    gem's `Framer` parses, so it does not affect the gem.
- Bumped pinned upstream `pi-coding-agent` version to `0.84.3` (from
  `0.84.2`). This is a CLI/TUI/provider/extension fix batch; none of the
  changes alter the JSONL RPC command/response shapes this gem drives, so
  no gem API change is required.
  - v0.84.3 adds an optional Windows `powershell` tool, safer
    stage-verify-activate managed updates, and `/thinking` model/thinking
    controls (session-scoped selections persisted with `Ctrl+S`), plus a
    large batch of fixes. These are CLI/TUI/provider or TypeScript
    extension-API concerns, outside the JSONL RPC surface this Ruby client
    speaks.
  - v0.84.3 fixes JSON and RPC `toolcall_start` events omitting the tool
    call id and name (upstream #7953). This gem does not consume
    `toolcall_start` events, so it is unaffected and compatible as-is.
  - The v0.84.3 breaking change (renaming the `GoogleThinkingLevel` type to
    `GoogleApiThinkingLevel`) is a TypeScript SDK type, not part of the RPC
    protocol, so it does not affect this gem.
- Bumped pinned upstream `pi-coding-agent` version to `0.84.2` (from
  `0.84.1`). This is a CLI/TUI/provider/extension fix batch; none of the
  changes alter the JSONL RPC command/response shapes this gem drives, so
  no gem API change is required.
  - v0.84.2 adds fullscreen transcript search, a configurable
    `defaultTools` setting, and configurable fullscreen exit output, plus
    a large batch of fixes (managed-tool downloads delaying TUI startup,
    fullscreen search/scroll/selection, and many inherited provider fixes
    across OpenAI Responses, Google/Vertex, Bedrock, DeepSeek, and Mistral).
    All are CLI/TUI/provider or TypeScript extension-API concerns, outside
    the JSONL RPC surface this Ruby client speaks.
  - v0.84.2 fixes JSON and RPC `message_update` events dropping cumulative
    usage during streaming (upstream #7982). This gem does not read usage
    from streaming `message_update` deltas — it queries token usage via the
    `get_session_stats` RPC (`Session#session_stats`) — so it is unaffected
    and compatible as-is.

## [0.3.1] - 2026-08-07

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.84.1` (from
  `0.83.0`). This is a CLI/TUI/auth/provider/extension batch; none of the
  changes alter the JSONL RPC command/response shapes this gem drives, so
  no gem API change is required.
  - v0.84.1 adds the Qwen Token Plan Individual built-in provider, a
    `pi auth check` credential preflight command, fullscreen selection /
    scrolling improvements, and `terminate` support on blocked extension
    `tool_call` events, plus assorted fixes (Bun standalone startup, LaTeX
    spacing, fullscreen mouse volume, `Agent.reset()` during active runs).
    All are CLI/TUI/auth/provider or TypeScript extension-API concerns,
    outside the JSONL RPC surface this Ruby client speaks.
  - v0.84.0 (folded into this bump) is a CLI/TUI/provider/extension batch;
    none of the changes alter the JSONL RPC command/response shapes this
    gem drives, so no gem API change is required.
  - v0.84.0 changes the JSON/RPC `message_update` events to emit only
    `assistantMessageEvent` deltas, removing the cumulative `message` and
    `assistantMessageEvent.partial` fields (upstream #7290). This gem
    already assembles output from `text_delta` deltas
    (`Event#delta` reads `assistantMessageEvent["delta"]`) and never relied
    on the removed cumulative/partial fields, so it is compatible as-is.
  - Other headline changes — fullscreen TUI mode, Mermaid/LaTeX rendering,
    per-directory `AGENTS.override.md` context overrides, advanced custom
    model sampling, and the Baseten provider — are TUI/context/provider
    concerns outside the RPC surface this gem speaks.
  - The remaining breaking changes (renamed `ModelsRequestTransforms`, the
    v4 lane-based `Session`/`SessionRepo` harness APIs, remote-session
    client APIs, `ModelRegistry`/`ModelRuntime` signatures) are TypeScript
    library APIs consumed by native pi extensions, not the RPC protocol
    this Ruby client drives.

## [0.3.0] - 2026-07-31

### Added
- Transport death notification. When pi dies unexpectedly (OOM kill,
  missing binary after spawn, sandbox teardown), the client now learns
  immediately instead of waiting out the 30s ack / 300s event timeouts
  with a generic `TimeoutError`:
  - Transports may accept an `on_close:` callable alongside
    `on_message:`/`on_stderr:` and invoke it exactly once, with a short
    human-readable reason, when they reach a terminal state on their
    own — never for a caller-initiated `#close`. `Transport::Subprocess`
    implements this (reporting exit status or signal, and watching the
    child process itself so a descendant holding the stdout pipe open
    can't defer the notification). The contract is documented in
    `Transport` and the README's "Custom transports" section.
  - On notification, `Client` rejects in-flight request futures with the
    new `PiAgent::TransportClosedError` (a `ProtocolError` subclass with
    the reason on `#reason`) and wakes subscribers with a synthetic
    `Client::TRANSPORT_CLOSED_TYPE` message, which `Session` event
    streams re-raise as `TransportClosedError`. Later `request`/`notify`
    calls fail fast with the same error, and subscribers registered
    after the death get the notification replayed once.
  - Backward compatible: `Client#start` passes `on_close:` only when the
    factory accepts the keyword (or `**kwargs`); existing
    `(on_message:, on_stderr:)` factories keep their previous
    timeout-backstop behavior unchanged.
  - Subscriber callbacks are isolated during fanout: one raising
    subscriber no longer prevents the rest from receiving a message.

## [0.2.2] - 2026-07-30

### Added
- Added the optional `on_extension_ui_error` callback to `PiAgent.open`,
  `PiAgent.session`, and `PiAgent::Client`. Applications can now observe an
  Extension UI handler exception together with its request while the dialog
  still fails closed as cancelled. Exceptions raised by the observer are also
  isolated so they cannot prevent the cancellation response.

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.83.0` (from
  `0.82.1`). This is a CLI/provider/extension batch; none of the changes
  alter the JSONL RPC command/response shapes this gem drives, so no gem
  API change is required.
  - Adds `pi auth print-api-key` and `pi auth print-bearer-token` for
    exporting configured credentials to external clients, with automatic
    OAuth refresh and configurable minimum token validity. These are CLI
    subcommands, outside the RPC surface this gem speaks.
  - Adds headless OpenRouter sign-in (paste the redirect URL or
    authorization code when the loopback callback is unavailable) and
    Claude Opus 5 on GitHub Copilot with adaptive thinking and a 1M
    context window. Both are provider/`/login` concerns.
  - Exposes the session's resolved model scope as `ctx.scopedModels` to
    extensions, adds a `"pending"` stop reason for partial streaming
    messages, and surfaces raw provider stop reasons across Google,
    Anthropic, Bedrock, Mistral, and OpenAI (unmapped terminal reasons now
    surface as provider errors). These are SDK/extension and
    provider-stream concerns; RPC event payloads still flow through
    `PiAgent::Event` transparently.
  - **Breaking for TypeScript extensions only:** upstream upgraded bundled
    TypeBox aliases to 1.3.7, removing deprecated APIs (`Type.Base`,
    `Type.Awaited`, `Type.Promise`, `Type.AsyncIterator`, `Type.Iterator`,
    `Type.Options`, `Value.Mutate`) and fixing nullable-array tool-argument
    validation. This does not affect this Ruby gem, which does not author
    TypeBox schemas.
  - The remainder are inherited fixes (tool-output expansion status line,
    file-backed `SYSTEM.md`/`APPEND_SYSTEM.md` startup listing, worktree
    context double-load, llama.cpp usage accounting, session replacement
    during active responses, Git package install retries, `/model`
    selector, direct RPC bash bypassing `user_bash` handlers, resource
    metadata, and assorted provider fixes) that leave the RPC contract
    unchanged.

## [0.2.1] - 2026-07-25

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.82.1` (from
  `0.81.1`, rolling up `0.82.0` and `0.82.1`). This is a provider/tooling
  and reliability batch; none of the changes alter the JSONL RPC
  command/response shapes this gem drives, so no gem API change is required.
  - `0.82.1` adds Claude Opus 5 (Anthropic and Amazon Bedrock, with
    adaptive thinking), `ANTHROPIC_AUTH_TOKEN` bearer auth for
    Anthropic-compatible gateways, and faster/more resilient model
    catalogs (pi.dev revalidates with `If-None-Match`). It exposes the
    `outputPad` setting to custom message renderers and fixes
    compaction/branch summaries for header-only auth providers, `/models`
    hiding of unavailable scoped models, startup context-file `EISDIR`
    warnings, and llama.cpp catalog persistence. All provider/SDK/TUI
    concerns, leaving the RPC contract unchanged.
  - `0.82.0` details follow.
  - Adds constrained tool sampling (`Tool.constrainedSampling` with strict
    JSON Schema and OpenAI Lark/regex grammars) plus `supportsGrammarTools`
    / `supportsStrictTools` model capability metadata. This is an
    SDK/extension tool-configuration concern, not part of the RPC surface.
  - Adds OpenRouter OAuth PKCE and Kimi Code subscription sign-in via
    `/login`, and exposes `PI_SESSION_ID`, `PI_SESSION_FILE`, `PI_PROVIDER`,
    `PI_MODEL`, and `PI_REASONING_LEVEL` to commands run by built-in and
    factory-created bash tools.
  - Adds streaming `bash_execution_update` events for direct RPC bash
    commands, correlated with request IDs. These flow through
    `PiAgent::Event` transparently — it preserves the native payload on
    `#raw` and exposes `#type` as a symbol — so no gem change is needed to
    consume them.
  - The remainder are inherited provider/retry/model-catalog fixes (DNS
    lookup retries, OpenRouter cache breakpoints, protobufjs 7.6.5 security
    bump, catalog mtime and llama.cpp context fixes) that leave the RPC
    contract unchanged.

## [0.2.0] - 2026-07-23

Minor (not patch) release: besides the stream-truncation fix, the block form
of `Session#follow_up` and stream concurrency behave differently (see
Changed).

### Fixed
- `Session#prompt`, `#follow_up`, `#events`, and `#run` now drain through
  `agent_settled` instead of stopping at the first `agent_end`. Since pi
  0.80.4, `agent_end` marks only one low-level run and may be followed by an
  automatic retry, compaction retry, or queued continuation; stopping there
  could unsubscribe early and silently drop the final response events.

### Changed
- The block form of `Session#follow_up` now uses pi's streaming-aware `prompt`
  command, so sequential follow-ups start when the session is idle while
  the blockless form remains a direct, queue-only `follow_up` RPC command for
  active runs. High-level streams are now single-flight per session because
  pi events have no run IDs; overlapping streams raise `SessionError` instead
  of potentially consuming another run's `agent_settled` event.

## [0.1.18] - 2026-07-21

### Added
- `Session#available_thinking_levels`, wrapping the upstream
  `get_available_thinking_levels` RPC command (added in pi `0.81.0`).
  Returns the thinking levels supported by the current model as an array of
  strings (e.g. `["off", "low", "medium", "high"]`), or `["off"]` for a
  model without reasoning support. Complements the existing `set_thinking`.

### Changed
- Bumped pinned upstream `pi-coding-agent` version to `0.81.1` (from
  `0.80.10`), covering both `0.81.0` and `0.81.1`.
  - `0.81.0` adds local llama.cpp model management, full provider
    extensions (extensions can register complete pi-ai providers), Qwen
    Token Plan built-in providers, and expanded usage accounting for
    tools, compaction, and branch summaries. The one change touching the
    JSONL RPC surface this gem drives is the new
    `get_available_thinking_levels` command, now exposed as
    `Session#available_thinking_levels`.
  - `0.81.1` adds resilient compaction/branch summaries that retry
    transient provider failures, emitting new `summarization_retry_*`
    lifecycle events (`summarization_retry_scheduled`,
    `summarization_retry_attempt_start`, `summarization_retry_finished`) to
    RPC consumers, plus checksummed release source archives. The retry
    events flow through `PiAgent::Event` transparently — it preserves the
    native payload on `#raw` and exposes `#type` as a symbol — so no gem
    change is needed to consume them.
  - No RPC commands or responses changed shape across either release, so
    the rest is provider/model/accounting concerns that leave the existing
    contract unchanged.

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
