# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
