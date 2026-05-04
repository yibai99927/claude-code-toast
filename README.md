# Claude Code Windows Notify

[English](README.md) | [中文](README.zh-CN.md)

Native Windows toast notifications for [Claude Code](https://code.claude.com) CLI — with emoji titles, Chinese/English body text, IM webhook forwarding, and zero external dependencies.

> Pure PowerShell 5.1 · WinRT Toast + Balloon Tip fallback · Plugin-based · Dedup & quiet hours · Webhooks (WeChat Work / Telegram / Discord / Feishu / QQ)

---

## Features

- **8 hook events** — Stop, StopFailure, Notification, PermissionRequest, PreToolUse (AskUserQuestion + ExitPlanMode), SubagentStop, TaskCompleted
- **Native Windows toast** — slides in from bottom-right with custom Claude Code icon and AUMID
- **Balloon tip fallback** — system-tray popup if WinRT toast is unavailable
- **System sounds** — different audio cues per severity (info / warning / error)
- **Emoji + i18n** — emoji icons in titles, Chinese body text, fully PS 5.1 compatible
- **Plugin-based** — install via `/plugin install`, auto-merged hooks, no manual settings.json editing
- **Deduplication** — suppresses duplicate notifications within a configurable window (default 5 s)
- **Quiet hours** — optional time window to mute low-severity notifications
- **IM webhook forwarding** — forward notifications to WeChat Work, Telegram, Discord, Feishu, QQ (Qmsg), or any HTTP-compatible service
- **Zero dependencies** — no Node.js, Python, Go, Bun, or external PowerShell modules required

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built-in)
- [Claude Code](https://code.claude.com) CLI

## Quick Start

```
# 1. Add marketplace (one time)
/plugin marketplace add yibai99927/claude-code-toast

# 2. Install plugin
/plugin install claude-code-toast@claude-code-toast
```

Then run the one-time Windows setup (Start Menu shortcut for toast identity):

```powershell
# Locate the plugin in cache and run setup
$pluginRoot = (Get-ChildItem "$env:USERPROFILE\.claude\plugins\cache\claude-code-toast\claude-code-toast" -Directory | Sort-Object Name -Descending | Select-Object -First 1).FullName
powershell -NoProfile -ExecutionPolicy Bypass -File "$pluginRoot\setup.ps1"
```

That's it. Every time Claude finishes a response, you'll get a native toast notification.

> **Alternative (clone + install)**: `git clone https://github.com/yibai99927/claude-code-toast.git && cd claude-code-toast && powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1` — then enable via `enabledPlugins` in `~/.claude/settings.json`.

## Architecture

```
  Claude Code hooks                    claude-code-toast
  ─────────────────                    ──────────────────
                                       
  settings.json  ──Stop──────────────►  ┌──────────────────┐
                 ──StopFailure───────►  │                  │
                 ──Notification──────►  │  notify-handler  │
                 ──PermissionRequest─►  │     .ps1         │
                 ──PreToolUse────────►  │                  │
                 ──SubagentStop──────►  │  (single entry   │
                 ──TaskCompleted─────►  │   point for all  │
                                        │   hook events)   │
                                        └──────┬───────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  Event Classifier    │
                                    │  (hook_event_name    │
                                    │   → notify type)     │
                                    └──────────┬──────────┘
                                               │
                          ┌────────────────────┼────────────────────┐
                          │                    │                    │
                     Dedup check         Severity gate        Quiet hours
                          │                    │                    │
                          └────────────────────┼────────────────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  Message Builder     │
                                    │  (emoji + Chinese)   │
                                    └──────────┬──────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  Delivery            │
                                    │  1. WinRT Toast      │
                                    │  2. Balloon Tip      │
                                    │  3. Console + Sound  │
                                    └─────────────────────┘
```

**Design principle**: all hook events call a single PowerShell script. The handler reads stdin JSON, classifies the event, applies filtering (dedup / severity / quiet hours), builds the notification message, and delivers via the first available backend.

## Notification Types

| Hook Event | Trigger | Title | Sound |
|---|---|---|---|
| `Stop` | Claude finishes responding | ✅ 任务完成 | Asterisk |
| `StopFailure` | Claude encounters an error | ❌ 执行异常 | Hand |
| `Notification` | Claude is idle / waiting | ⏳ 等待输入 | Asterisk |
| `PermissionRequest` | Claude needs tool approval | 🔐 请求权限 | Exclamation |
| `PreToolUse: AskUserQuestion` | Claude asks a question | 💬 Claude 提问 | Question |
| `PreToolUse: ExitPlanMode` | Plan is ready for review | 📋 计划就绪 | Exclamation |
| `SubagentStop` | Sub-agent completes | 🤖 子任务完成 | Asterisk |
| `TaskCompleted` | Team task marked done | 🤖 子任务完成 | Asterisk |
| `SessionStart` | Session begins *(disabled)* | ▶️ 会话开始 | Asterisk |
| `SessionEnd` | Session ends *(disabled)* | ⏹️ 会话结束 | Asterisk |

> **Why PreToolUse for AskUserQuestion / ExitPlanMode?**
> In Plan Mode, `Notification` may not fire reliably for `AskUserQuestion` ([claude-code#42487](https://github.com/anthropics/claude-code/issues/42487)). We monitor `PreToolUse` with tool-name matchers as a reliable fallback.

## Configuration

Edit `~/.claude/claude-code-toast/notify-config.json`:

```jsonc
{
  "enableToast": true,          // Enable WinRT toast + balloon tip
  "enableSound": true,          // Play system sounds
  "quietHours": {
    "enabled": false,           // Mute during specific hours
    "start": "22:00",
    "end":   "08:00"
  },
  "minSeverity": "low",         // Minimum level: low | medium | high
  "dedupeSeconds": 5,           // Suppress duplicate events within N seconds
  "showCwd": true,              // Show project directory name in body
  "showSummary": true,          // Show last assistant message preview (Stop event)
  "summaryMaxChars": 150,       // Truncate summary at N characters
  "debugLog": false,            // Log full payload JSON
  "language": "zh-CN",          // "en" for English, "zh-CN" for Chinese
  "events": {
    "Stop":                 {"enabled": true, "severity": "low"},
    "StopFailure":          {"enabled": true, "severity": "high"},
    "Notification":         {"enabled": true, "severity": "medium"},
    "PermissionRequest":    {"enabled": true, "severity": "high"},
    "PreToolUse:AskUserQuestion": {"enabled": true, "severity": "high"},
    "PreToolUse:ExitPlanMode":    {"enabled": true, "severity": "high"},
    "SubagentStop":         {"enabled": false, "severity": "low"},
    "TaskCompleted":        {"enabled": true, "severity": "low"},
    "SessionStart":         {"enabled": false, "severity": "low"},
    "SessionEnd":           {"enabled": false, "severity": "low"}
  },
  "webhooks": {
    "enabled": false,
    "endpoints": [
      {"name": "wecom-example",  "type": "wecom",    "url": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY",        "at_mobiles": [], "at_all": false, "events": ["StopFailure", "PermissionRequest"]},
      {"name": "telegram-example","type": "telegram", "url": "https://api.telegram.org/botYOUR_BOT_TOKEN/sendMessage",                "chat_id": "YOUR_CHAT_ID",       "events": ["StopFailure"]},
      {"name": "discord-example", "type": "discord",  "url": "https://discord.com/api/webhooks/YOUR_WEBHOOK_ID/YOUR_TOKEN",                                             "events": ["StopFailure"]},
      {"name": "feishu-example",  "type": "feishu",   "url": "https://open.feishu.cn/open-apis/bot/v2/hook/YOUR_TOKEN",                                                  "events": ["StopFailure"]},
      {"name": "qq-qmsg-example", "type": "http",     "url": "https://qmsg.zendee.cn/api/v2/send/YOUR_KEY",                                                              "events": ["StopFailure"]}
    ]
  }
}
```

## Webhooks

Forward notifications to IM platforms via webhook. Each endpoint can filter which events trigger it.

**Supported platforms:**

| Type | Platform | Extra Fields |
|------|----------|-------------|
| `wecom` | WeChat Work (企业微信) | `at_mobiles`, `at_all` |
| `telegram` | Telegram | `chat_id` |
| `discord` | Discord | — |
| `feishu` | Feishu (飞书) | — |
| `http` | QQ Qmsg / generic HTTP | — |

**Example:** Receive `StopFailure` and `PermissionRequest` alerts on WeChat Work:

```jsonc
"webhooks": {
  "enabled": true,
  "endpoints": [
    {
      "name": "my-wecom",
      "type": "wecom",
      "url": "https://qyapi.weixin.qq.com/cgi-bin/webhook/send?key=YOUR_KEY",
      "at_mobiles": ["13800138000"],
      "at_all": false,
      "events": ["StopFailure", "PermissionRequest"]
    }
  ]
}
```

Add this to your `notify-config.json`. The full config template with all platform examples is generated by `setup.ps1`.

## Managing

- **Enable/disable**: `/plugin disable claude-code-toast@claude-code-toast` / `/plugin enable claude-code-toast@claude-code-toast`
- **Update**: `/plugin update claude-code-toast@claude-code-toast`

## Uninstall

```
# 1. Remove plugin (hooks auto-removed)
/plugin uninstall claude-code-toast@claude-code-toast

# 2. Clean up shortcut and user data (optional)
powershell -NoProfile -ExecutionPolicy Bypass -File setup-uninstall.ps1
```

## File Structure

```
claude-code-toast/
  .claude-plugin/
    plugin.json             ← plugin metadata
    marketplace.json        ← marketplace definition
  hooks/
    hooks.json              ← hook declarations (auto-merged by Claude Code)
  notify-handler.ps1        ← main handler (called by all hooks)
  setup.ps1                 ← one-time AUMID shortcut + config setup
  setup-uninstall.ps1       ← shortcut + user data cleanup
  notify-config.json        ← default config template
  ClaudeCode-logo.ico       ← toast notification icon
  ClaudeCode-logo.jpg       ← original logo source
  README.md                 ← this file
  README.zh-CN.md           ← Chinese version
  logs/                     ← runtime logs (gitignored, stored in ~/.claude/claude-code-toast/)
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| No notification at all | Plugin not enabled | Run `/plugin list` to verify; check `enabledPlugins` in settings.json |
| Sound but no toast | Focus Assist or AUMID not set up | Check Windows notification settings; re-run `setup.ps1` |
| Toast shows wrong icon | Shortcut missing or wrong AUMID | Re-run `setup.ps1`; check `%APPDATA%\...\claude-code-toast\claude-code-toast.lnk` |
| Chinese text is garbled | PS 5.1 encoding issue | Ensure `.ps1` is UTF-8 with BOM (plugin handles this) |
| Duplicate notifications | Old hooks in settings.json conflicting | Remove old hook entries from `~/.claude/settings.json` |
| Permission not triggering | Permission denied before hook fires | Normal — hook fires *before* the permission dialog |

Check `~/.claude/claude-code-toast/logs/notify.log` for detailed delivery status.

## Acknowledgments

Inspired by [claude-notifications-go](https://github.com/777genius/claude-notifications-go) by @777genius — a cross-platform notification plugin for Claude Code written in Go. This project reimagines the concept as a pure PowerShell implementation for Windows.

## License

MIT
