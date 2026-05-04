# Claude Code Windows Notify

Native Windows toast notifications for [Claude Code](https://code.claude.com) CLI — with emoji titles, Chinese/English body text, and zero external dependencies.

> Pure PowerShell 5.1 · WinRT Toast + Balloon Tip fallback · Safe hook merging · Dedup & quiet hours

---

## Features

- **8 hook events** — Stop, StopFailure, Notification, PermissionRequest, PreToolUse (AskUserQuestion + ExitPlanMode), SubagentStop, TaskCompleted
- **Native Windows toast** — slides in from bottom-right with custom Claude Code icon and AUMID
- **Balloon tip fallback** — system-tray popup if WinRT toast is unavailable
- **System sounds** — different audio cues per severity (info / warning / error)
- **Emoji + i18n** — emoji icons in titles, Chinese body text, fully PS 5.1 compatible
- **Safe installer** — merges hooks into `settings.json` without overwriting existing entries; re-runnable
- **Deduplication** — suppresses duplicate notifications within a configurable window (default 5 s)
- **Quiet hours** — optional time window to mute low-severity notifications
- **Zero dependencies** — no Node.js, Python, Go, Bun, or external PowerShell modules required

## Requirements

- Windows 10 or 11
- PowerShell 5.1 (built-in)
- [Claude Code](https://code.claude.com) CLI

## Quick Start

```powershell
# Clone the repo
git clone https://github.com/YOUR_USER/claude-code-notify.git
cd claude-code-notify

# Install
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-notify.ps1

# Verify in Claude Code
/claude hooks
```

That's it. Every time Claude finishes a response, you'll get a native toast notification.

## Architecture

```
  Claude Code hooks                    claude-code-notify
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

Edit `notify-config.json` in the project directory:

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
  "events": {
    "Stop":                 {"enabled": true, "severity": "low"},
    "StopFailure":          {"enabled": true, "severity": "high"},
    "Notification":         {"enabled": true, "severity": "medium"},
    "PermissionRequest":    {"enabled": true, "severity": "high"},
    "PreToolUse:AskUserQuestion": {"enabled": true, "severity": "high"},
    "PreToolUse:ExitPlanMode":    {"enabled": true, "severity": "high"},
    "SubagentStop":         {"enabled": true, "severity": "low"},
    "TaskCompleted":        {"enabled": true, "severity": "low"},
    "SessionStart":         {"enabled": false, "severity": "low"},
    "SessionEnd":           {"enabled": false, "severity": "low"}
  }
}
```

## Uninstall

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-notify.ps1
```

This removes all notification hooks from `~/.claude/settings.json` and deletes the shortcut. A backup is created automatically.

## File Structure

```
claude-code-notify/
  README.md               ← this file
  notify-handler.ps1       ← main handler (called by all hooks)
  install-notify.ps1       ← safe settings.json merger
  uninstall-notify.ps1     ← hook remover
  notify-config.json       ← user configuration
  ClaudeCode-logo.ico      ← toast notification icon
  ClaudeCode-logo.jpg      ← original logo source
  logs/                    ← runtime logs (gitignored)
```

## Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| No notification at all | Hook not configured | Run `/hooks` in Claude Code; re-run installer |
| Sound but no toast | Focus Assist or notification suppressed | Check Windows notification settings for PowerShell |
| Toast shows wrong icon | Shortcut missing or wrong AUMID | Re-run installer; check `%APPDATA%\...\ClaudeCodeNotify\claude-notify.lnk` |
| Chinese text is garbled | PS 5.1 encoding issue | Ensure `.ps1` is UTF-8 with BOM (installer handles this) |
| Duplicate notifications | Multiple hook entries | Re-run installer (it detects and skips duplicates) |
| Permission not triggering | Permission denied before hook fires | Normal — hook fires *before* the permission dialog |

Check `logs/notify.log` for detailed delivery status.

## License

MIT

---

# 中文说明

## Claude Code Windows 通知系统

为 [Claude Code](https://code.claude.com) CLI 提供原生 Windows toast 通知 — 支持 emoji 标题、中文正文、零外部依赖。

### 快速安装

```powershell
git clone https://github.com/YOUR_USER/claude-code-notify.git
cd claude-code-notify
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-notify.ps1
```

### 通知类型

| 触发事件 | 标题 | 含义 |
|---|---|---|
| Stop | ✅ 任务完成 | Claude 完成响应 |
| StopFailure | ❌ 执行异常 | Claude 异常停止 |
| Notification | ⏳ 等待输入 | Claude 等待你的回复 |
| PermissionRequest | 🔐 请求权限 | 需要批准工具执行 |
| PreToolUse: AskUserQuestion | 💬 Claude 提问 | Claude 有问题需要回答 |
| PreToolUse: ExitPlanMode | 📋 计划就绪 | 计划已生成，等待确认 |
| SubagentStop / TaskCompleted | 🤖 子任务完成 | 子 Agent 或团队任务完成 |

### 工作原理

所有 Claude Code hooks 调用同一个 PowerShell 脚本 `notify-handler.ps1`。脚本从 stdin 读取 JSON payload，分类事件，应用去重/严重度过滤/静音时段，构建通知消息，然后通过 WinRT Toast 或气泡提示弹出。

### 配置

编辑项目目录下的 `notify-config.json`，可控制每个事件的开关、严重度、免打扰时段等。详见上方英文配置章节。

### 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-notify.ps1
```
