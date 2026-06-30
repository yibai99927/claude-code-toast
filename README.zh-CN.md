# Claude Code Windows 通知系统

[English](README.md) | [中文](README.zh-CN.md)

为 [Claude Code](https://code.claude.com) CLI 提供原生 Windows toast 通知 — 支持 emoji 标题、中文正文、IM webhook 转发、零外部依赖。

> 纯 PowerShell 5.1 · WinRT Toast + 气泡提示回退 · 插件式安装 · 去重 & 免打扰 · Webhooks（企业微信 / Telegram / Discord / 飞书 / QQ）

---

## 功能特性

- **10 种 hook 事件** — Stop、StopFailure、Notification、PermissionRequest、PreToolUse（AskUserQuestion + ExitPlanMode）、SubagentStop、TaskCompleted、SessionStart、SessionEnd
- **原生 Windows toast** — 右下角滑出，使用自定义 Claude Code 图标和专属 AUMID
- **气泡提示回退** — WinRT toast 不可用时自动使用系统托盘气泡
- **系统声音** — 按严重程度区分提示音（信息 / 警告 / 错误）
- **Emoji + 中文** — 标题带 emoji 图标，中文正文，完全兼容 PS 5.1
- **插件式安装** — 通过 `/plugin install` 一键安装，hooks 自动合并，无需手动编辑 settings.json
- **去重机制** — 可配置时间窗口内抑制重复通知（默认 5 秒）
- **免打扰时段** — 可选静音时段，低严重度事件在此期间静音
- **IM webhook 转发** — 将通知转发到企业微信、Telegram、Discord、飞书、QQ（Qmsg）或任意 HTTP 兼容服务
- **零依赖** — 无需 Node.js、Python、Go、Bun 或外部 PowerShell 模块

## 系统要求

- Windows 10 或 11
- PowerShell 5.1（系统自带）
- [Claude Code](https://code.claude.com) CLI

## 快速开始

```
# 1. 添加市场（仅需一次）
/plugin marketplace add yibai99927/claude-code-toast

# 2. 安装插件
/plugin install claude-code-toast@claude-code-toast
```

搞定。首次通知触发时，插件会自动完成 Windows 快捷方式注册和配置文件初始化（无需手动运行 setup）。每次 Claude 完成响应，你都会收到原生 toast 通知。

> **备选方式（克隆 + 安装）**：`git clone https://github.com/yibai99927/claude-code-toast.git && cd claude-code-toast && powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1` — 然后在 `~/.claude/settings.json` 的 `enabledPlugins` 中启用。
>
> **手动运行 setup**（如需）：`powershell -NoProfile -ExecutionPolicy Bypass -File "<plugin-path>\setup.ps1"` — 仅在自动 setup 未生效时使用。

## 架构

```
  Claude Code hooks                    claude-code-toast
  ─────────────────                    ──────────────────

  settings.json  ──Stop──────────────►  ┌──────────────────┐
                 ──StopFailure───────►  │                  │
                 ──Notification──────►  │  notify-handler  │
                 ──PermissionRequest─►  │     .ps1         │
                 ──PreToolUse────────►  │                  │
                 ──SubagentStop──────►  │  (所有 hook 事件  │
                 ──TaskCompleted─────►  │   的统一入口)     │
                 ──SessionStart──────►  │                  │
                 ──SessionEnd────────►  │                  │
                                        └──────┬───────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  事件分类器           │
                                    │  (hook_event_name    │
                                    │   → 通知类型)        │
                                    └──────────┬──────────┘
                                               │
                          ┌────────────────────┼────────────────────┐
                          │                    │                    │
                      去重检查             严重度过滤            免打扰时段
                          │                    │                    │
                          └────────────────────┼────────────────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  消息构建器           │
                                    │  (emoji + 中文)      │
                                    └──────────┬──────────┘
                                               │
                                    ┌──────────┴──────────┐
                                    │  投递                │
                                    │  1. WinRT Toast      │
                                    │  2. 气泡提示          │
                                    │  3. 控制台 + 声音    │
                                    └─────────────────────┘
```

**设计原则**：所有 hook 事件调用同一个 PowerShell 脚本。处理器从 stdin 读取 JSON，分类事件，应用过滤（去重 / 严重度 / 免打扰），构建通知消息，通过第一个可用的后端投递。

## 通知类型

| Hook 事件 | 触发时机 | 标题 | 声音 |
|---|---|---|---|
| `Stop` | Claude 完成响应 | ✅ 任务完成 | Asterisk |
| `StopFailure` | Claude 遇到错误 | ❌ 执行异常 | Hand |
| `Notification` | Claude 空闲/等待 | ⏳ 等待输入 | Asterisk |
| `PermissionRequest` | Claude 请求工具权限 | 🔐 请求权限 | Exclamation |
| `PreToolUse: AskUserQuestion` | Claude 提问 | 💬 Claude 提问 | Question |
| `PreToolUse: ExitPlanMode` | 计划已就绪 | 📋 计划就绪 | Exclamation |
| `SubagentStop` | 子 agent 完成 | 🤖 子任务完成 | Asterisk |
| `TaskCompleted` | 团队任务标记完成 | 🤖 子任务完成 | Asterisk |
| `SessionStart` | 会话开始 *（默认禁用）* | ▶️ 会话开始 | Asterisk |
| `SessionEnd` | 会话结束 *（默认禁用）* | ⏹️ 会话结束 | Asterisk |

> 如需关闭子任务完成通知，请同时关闭 `SubagentStop` 和 `TaskCompleted`；主任务完成通知保留使用 `Stop`。

> **为什么用 PreToolUse 监听 AskUserQuestion / ExitPlanMode？**
> Plan Mode 下 `Notification` 事件对 `AskUserQuestion` 可能不触发（[claude-code#42487](https://github.com/anthropics/claude-code/issues/42487)）。我们通过 `PreToolUse` 配合 tool-name matcher 作为可靠兜底。

## 配置

编辑 `~/.claude/claude-code-toast/notify-config.json`：

```jsonc
{
  "enableToast": true,          // 启用 WinRT toast + 气泡提示
  "enableSound": true,          // 播放系统声音
  "quietHours": {
    "enabled": false,           // 在指定时段静音
    "start": "22:00",
    "end":   "08:00"
  },
  "minSeverity": "low",         // 最低通知等级: low | medium | high
  "dedupeSeconds": 5,           // N 秒内抑制重复事件
  "showCwd": true,              // Body 中显示项目目录名
  "showSummary": true,          // 显示最后回复摘要（Stop 事件）
  "summaryMaxChars": 150,       // 摘要截断长度
  "debugLog": false,            // 记录完整 payload JSON
  "language": "zh-CN",          // "en" 为英文，"zh-CN" 为中文
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
      {"name": "qq-qmsg-example", "type": "qmsg",     "url": "https://qmsg.zendee.cn/api/v2/send/YOUR_KEY",                                                              "events": ["StopFailure"]}
    ]
  }
}
```

## Webhooks

将通知通过 webhook 转发到 IM 平台。每个端点可按事件过滤。

**支持的平台：**

| 类型 | 平台 | 额外字段 |
|------|------|---------|
| `wecom` | 企业微信 | `at_mobiles`, `at_all` |
| `telegram` | Telegram | `chat_id` |
| `discord` | Discord | — |
| `feishu` | 飞书 | — |
| `qmsg` | QQ Qmsg | — |
| `http` | 通用 JSON webhook | 发送 `{"content": "..."}` |

**示例：** 在企业微信上接收 `StopFailure` 和 `PermissionRequest` 告警：

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

将以上内容添加到 `notify-config.json` 中。包含所有平台示例的完整配置模板由 `setup.ps1` 生成。

## 管理

- **启用/禁用**：`/plugin disable claude-code-toast@claude-code-toast` / `/plugin enable claude-code-toast@claude-code-toast`
- **更新**：`/plugin update claude-code-toast@claude-code-toast`

## 卸载

```
# 1. 移除插件（hooks 自动清除）
/plugin uninstall claude-code-toast@claude-code-toast

# 2. 清理快捷方式和用户数据（可选）
powershell -NoProfile -ExecutionPolicy Bypass -File setup-uninstall.ps1
```

## 文件结构

```
claude-code-toast/
  .claude-plugin/
    plugin.json             ← 插件元数据
    marketplace.json        ← 市场定义
  hooks/
    hooks.json              ← hook 声明（Claude Code 运行时自动合并）
  notify-handler.ps1        ← 主处理器（所有 hooks 调用）
  setup.ps1                 ← 一次性 AUMID 快捷方式 + 配置初始化
  setup-uninstall.ps1       ← 快捷方式 + 用户数据清理
  notify-config.json        ← 默认配置模板
  ClaudeCode-logo.ico       ← toast 通知图标
  README.md                 ← 英文说明
  README.zh-CN.md           ← 中文说明（本文件）
  logs/                     ← 运行日志（gitignore，存储于 ~/.claude/claude-code-toast/）
```

## 故障排查

| 现象 | 可能原因 | 解决方法 |
|---|---|---|
| 完全没通知 | 插件未启用 | 运行 `/plugin list` 确认；检查 settings.json 中 `enabledPlugins` |
| 有声音但无弹窗 | 专注助手或 AUMID 未设置 | 检查 Windows 通知设置；重新运行 `setup.ps1` |
| Toast 图标不对 | 快捷方式缺失或 AUMID 错误 | 重新运行 `setup.ps1`；检查 `%APPDATA%\...\claude-code-toast\claude-code-toast.lnk` |
| 中文乱码 | PS 5.1 编码问题 | 确保 `.ps1` 为 UTF-8 with BOM（插件已处理） |
| 重复通知 | settings.json 中旧 hooks 冲突 | 从 `~/.claude/settings.json` 中移除旧的 hook 条目 |
| 权限通知未触发 | Hook 在权限弹窗前触发 | 正常行为 — hook 在权限弹窗*之前*触发 |

查看 `~/.claude/claude-code-toast/logs/notify.log` 了解详细投递状态。

## 致谢

本项目受 [claude-notifications-go](https://github.com/777genius/claude-notifications-go)（@777genius）启发 — 一个用 Go 编写的跨平台 Claude Code 通知插件。本项目以纯 PowerShell 重新实现，专为 Windows 优化。

## License

MIT
