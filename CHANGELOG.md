# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
