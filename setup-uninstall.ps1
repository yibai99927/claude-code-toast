#Requires -Version 5.1
<#
.SYNOPSIS
  Cleanup script for claude-code-toast plugin.
  Removes the Start Menu shortcut and user data directory.
  Hook removal is handled by /plugin uninstall.
#>

$ErrorActionPreference = 'Continue'
$UserDataDir = "$env:USERPROFILE\.claude\claude-code-toast"
$ShortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\claude-code-toast"

Write-Host '=== claude-code-toast Cleanup ===' -ForegroundColor Cyan
Write-Host ''

# ===================================================================
# 1. Remove Start Menu shortcut
# ===================================================================
Write-Host '[1/2] Removing Start Menu shortcut...' -ForegroundColor Yellow

if (Test-Path $ShortcutDir) {
    Remove-Item $ShortcutDir -Recurse -Force
    Write-Host "  Removed: $ShortcutDir" -ForegroundColor Green
} else {
    Write-Host "  Not found: $ShortcutDir" -ForegroundColor DarkYellow
}

Write-Host ''

# ===================================================================
# 2. Remove user data (config + logs)
# ===================================================================
Write-Host '[2/2] Removing user data...' -ForegroundColor Yellow

if (Test-Path $UserDataDir) {
    Remove-Item $UserDataDir -Recurse -Force
    Write-Host "  Removed: $UserDataDir" -ForegroundColor Green
} else {
    Write-Host "  Not found: $UserDataDir" -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host '=== Cleanup Complete ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'To fully uninstall the plugin, also run in Claude Code:' -ForegroundColor White
Write-Host '  /plugin uninstall claude-code-toast@claude-code-toast' -ForegroundColor White
Write-Host ''
