# Changelog

All notable changes to this project are documented in this file.

## [1.2.0] - 2026-06-30

### Added
- Modular `lib/` architecture split from monolithic handler
- File-based dedup cache (`.dedup-cache.json`) — fixes cross-process dedup
- Subtask dedup by notify type instead of raw event name
- Async webhook delivery via `webhook-worker.ps1`
- Toast custom icon (`appLogoOverride`) and click-to-open-project-folder action
- Balloon tip fallback uses `ClaudeCode-logo.ico`
- Per-event `respectQuietHours` config option
- Webhook platforms: DingTalk, Slack, Bark, PushPlus
- Webhook URL validation and per-platform message length limits
- Setup status tracking (`.setup-status.json`) with shortcut retry
- JSON Schema: `notify-config.schema.json`
- Unit tests: `tests/run-tests.ps1`
- Version read from `plugin.json` at runtime

### Changed
- `TaskCompleted` default disabled (aligned with `SubagentStop`)
- Debug logs sanitize `tool_input` secrets
- Bump plugin/marketplace version to 1.2.0

### Fixed
- Dedup window now effective across separate hook invocations
- Telegram webhook no longer uses unsafe HTML parse mode (from 1.1.0)

## [1.1.0]

- SessionStart/SessionEnd hooks registered
- Auto-setup on first notification
- Qmsg webhook type
- Marketplace version sync

## [1.0.0]

- Initial plugin release with WinRT toast, webhooks, quiet hours
