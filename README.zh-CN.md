# Claude Code Windows 通知系统

[English](README.md) | [中文](README.zh-CN.md)

为 [Claude Code](https://code.claude.com) CLI 提供原生 Windows toast 通知 — 支持 emoji 标题、中文正文、零外部依赖。

> 纯 PowerShell 5.1 · WinRT Toast + 气泡提示回退 · 安全合并 hooks · 去重 & 免打扰

---

## 功能特性

- **8 种 hook 事件** — Stop、StopFailure、Notification、PermissionRequest、PreToolUse（AskUserQuestion + ExitPlanMode）、SubagentStop、TaskCompleted
- **原生 Windows toast** — 右下角滑出，使用自定义 Claude Code 图标和专属 AUMID
- **气泡提示回退** — WinRT toast 不可用时自动使用系统托盘气泡
- **系统声音** — 按严重程度区分提示音（信息 / 警告 / 错误）
- **Emoji + 中文** — 标题带 emoji 图标，中文正文，完全兼容 PS 5.1
- **安全安装器** — 合并 hooks 到 `settings.json` 时不覆盖已有配置，可重复运行
- **去重机制** — 可配置时间窗口内抑制重复通知（默认 5 秒）
- **免打扰时段** — 可选静音时段，低严重度事件在此期间静音
- **零依赖** — 无需 Node.js、Python、Go、Bun 或外部 PowerShell 模块

## 系统要求

- Windows 10 或 11
- PowerShell 5.1（系统自带）
- [Claude Code](https://code.claude.com) CLI

## 快速开始

```powershell
# 克隆仓库
git clone https://github.com/yibai99927/claude-code-toast.git
cd claude-code-toast

# 安装
powershell -NoProfile -ExecutionPolicy Bypass -File .\install-notify.ps1

# 在 Claude Code 中验证
/claude hooks
```

搞定。每次 Claude 完成响应，你都会收到原生 toast 通知。

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

> **为什么用 PreToolUse 监听 AskUserQuestion / ExitPlanMode？**
> Plan Mode 下 `Notification` 事件对 `AskUserQuestion` 可能不触发（[claude-code#42487](https://github.com/anthropics/claude-code/issues/42487)）。我们通过 `PreToolUse` 配合 tool-name matcher 作为可靠兜底。

## 配置

编辑项目目录下的 `notify-config.json`：

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

## 卸载

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\uninstall-notify.ps1
```

此命令会从 `~/.claude/settings.json` 中移除所有通知 hooks 并删除快捷方式。自动创建备份。

## 文件结构

```
claude-code-toast/
  README.md               ← 英文说明
  README.zh-CN.md          ← 中文说明（本文件）
  notify-handler.ps1       ← 主处理器（所有 hooks 调用）
  install-notify.ps1       ← 安全安装器（合并 settings.json）
  uninstall-notify.ps1     ← 卸载器（移除 hooks）
  notify-config.json       ← 用户配置文件
  ClaudeCode-logo.ico      ← toast 通知图标
  ClaudeCode-logo.jpg      ← 原始 logo 素材
  logs/                    ← 运行日志（gitignore）
```

## 故障排查

| 现象 | 可能原因 | 解决方法 |
|---|---|---|
| 完全没通知 | Hook 未配置 | 在 Claude Code 中运行 `/hooks`；重新运行安装器 |
| 有声音但无弹窗 | 专注助手或通知被禁用 | 检查 Windows 通知设置中 PowerShell 的权限 |
| Toast 图标不对 | 快捷方式缺失或 AUMID 错误 | 重新运行安装器；检查 `%APPDATA%\...\ClaudeCodeNotify\claude-notify.lnk` |
| 中文乱码 | PS 5.1 编码问题 | 确保 `.ps1` 为 UTF-8 with BOM（安装器已处理） |
| 重复通知 | 存在多个 hook 条目 | 重新运行安装器（自动检测并跳过重复） |
| 权限通知未触发 | Hook 在权限弹窗前触发 | 正常行为 — hook 在权限弹窗*之前*触发 |

查看 `logs/notify.log` 了解详细投递状态。

## License

MIT
