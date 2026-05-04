#Requires -Version 5.1
<#
.SYNOPSIS
  Uninstall the Claude Code Windows notification system.
  Removes hook entries from settings.json, deletes handler/config/shortcut.
  Safe — creates backup before modifying settings.json.
#>

$ErrorActionPreference = 'Stop'
$UserClaudeDir = "$env:USERPROFILE\.claude"
$ToolsDir = Join-Path $UserClaudeDir 'tools'
$HandlerPath = Join-Path $ToolsDir 'notify-handler.ps1'
$ConfigPath = Join-Path $UserClaudeDir 'notify-config.json'
$SettingsPath = Join-Path $UserClaudeDir 'settings.json'
$BackupDir = Join-Path $UserClaudeDir 'backups'
$ShortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ClaudeCodeNotify"

Write-Host '=== Claude Code Windows Notification Uninstaller ===' -ForegroundColor Cyan
Write-Host ''

$handlerCmdPattern = 'notify-handler.ps1'

# ===================================================================
# 1. Remove hooks from settings.json
# ===================================================================
Write-Host '[1/4] Removing hooks from settings.json...' -ForegroundColor Yellow

if (-not (Test-Path $SettingsPath)) {
    Write-Host '  No settings.json found — nothing to clean' -ForegroundColor DarkYellow
} else {
    # Backup
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $BackupDir "settings.json.before-uninstall-notify.$ts"
    Copy-Item $SettingsPath $backupPath -Force
    Write-Host "  Backup saved: $backupPath" -ForegroundColor Green

    try {
        $raw = Get-Content -Raw $SettingsPath
        $settings = if ([string]::IsNullOrWhiteSpace($raw)) { @{} } else { $raw | ConvertFrom-Json }
    } catch {
        Write-Error "Failed to parse settings.json: $_"
        exit 1
    }

    # Check for hooks section
    $props = $settings.PSObject.Properties
    if ($props.Name -notcontains 'hooks') {
        Write-Host '  No hooks section in settings.json — nothing to remove' -ForegroundColor DarkYellow
    } else {
        $removedCount = 0
        $allHooks = $settings.hooks
        $hookEventNames = @($allHooks.PSObject.Properties.Name)

        foreach ($eventName in $hookEventNames) {
            $matchers = @($allHooks.$eventName)
            $filtered = @()
            $matcherRemoved = 0

            foreach ($m in $matchers) {
                $mHooks = $m.hooks
                if ($null -eq $mHooks) {
                    $filtered += $m
                    continue
                }
                $filteredHooks = @()
                foreach ($h in $mHooks) {
                    $cmd = if ($h -is [PSCustomObject]) { $h.command } else { $h['command'] }
                    if ($cmd -and $cmd -match $handlerCmdPattern) {
                        $matcherRemoved++
                        $removedCount++
                    } else {
                        $filteredHooks += $h
                    }
                }
                # Keep matcher if it still has other hooks
                if ($filteredHooks.Count -gt 0) {
                    $newMatcher = @{ matcher = $m.matcher; hooks = $filteredHooks }
                    $filtered += $newMatcher
                } elseif ($matcherRemoved -eq 0) {
                    # No hooks were removed from this matcher, keep it as-is
                    $filtered += $m
                }
                # If matcher had only our hooks and they were all removed, drop the matcher entirely
            }

            if ($filtered.Count -gt 0) {
                $allHooks.$eventName = $filtered
            } else {
                # Remove the entire event key if no matchers remain
                $allHooks.PSObject.Properties.Remove($eventName)
            }
        }

        # If hooks is now empty, remove it entirely
        $remainingHookEvents = @($allHooks.PSObject.Properties.Name)
        if ($remainingHookEvents.Count -eq 0) {
            $settings.PSObject.Properties.Remove('hooks')
            Write-Host '  Hooks section removed (all empty)' -ForegroundColor Green
        }

        $settings | ConvertTo-Json -Depth 10 | Out-File -FilePath $SettingsPath -Encoding UTF8
        Write-Host "  Removed $removedCount hook handler(s)" -ForegroundColor Green
    }
}

Write-Host ''

# ===================================================================
# 2. Remove handler script
# ===================================================================
Write-Host '[2/4] Removing handler script...' -ForegroundColor Yellow

if (Test-Path $HandlerPath) {
    Remove-Item $HandlerPath -Force
    Write-Host "  Removed: $HandlerPath" -ForegroundColor Green
} else {
    Write-Host "  Not found: $HandlerPath" -ForegroundColor DarkYellow
}

Write-Host ''

# ===================================================================
# 3. Remove config file
# ===================================================================
Write-Host '[3/4] Removing notification config...' -ForegroundColor Yellow

if (Test-Path $ConfigPath) {
    Remove-Item $ConfigPath -Force
    Write-Host "  Removed: $ConfigPath" -ForegroundColor Green
} else {
    Write-Host "  Not found: $ConfigPath" -ForegroundColor DarkYellow
}

Write-Host ''

# ===================================================================
# 4. Remove Start Menu shortcut
# ===================================================================
Write-Host '[4/4] Removing Start Menu shortcut...' -ForegroundColor Yellow

if (Test-Path $ShortcutDir) {
    Remove-Item $ShortcutDir -Recurse -Force
    Write-Host "  Removed: $ShortcutDir" -ForegroundColor Green
} else {
    Write-Host "  Not found: $ShortcutDir" -ForegroundColor DarkYellow
}

Write-Host ''

# ===================================================================
# Done
# ===================================================================
Write-Host '=== Uninstall Complete ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Notification hooks have been removed from settings.json.' -ForegroundColor White
Write-Host 'Log files (if any) remain in ~/.claude/logs/ — delete manually if desired.' -ForegroundColor DarkGray
Write-Host ''
