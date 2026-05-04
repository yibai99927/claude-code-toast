#Requires -Version 5.1
<#
.SYNOPSIS
  Install the Claude Code Windows notification system.
.DESCRIPTION
  1. Creates Start Menu shortcut for toast identity.
  2. Copies notify-handler.ps1 to ~/.claude/tools/.
  3. Safely merges hook entries into ~/.claude/settings.json.
  4. Creates ~/.claude/notify-config.json with defaults if absent.
  5. Backs up settings.json before modification.
  Safe to run multiple times — detects duplicates and skips.
#>

$ErrorActionPreference = 'Stop'
$ProjectDir = "$env:USERPROFILE\claude-code-toast"
$UserClaudeDir = "$env:USERPROFILE\.claude"
$HandlerPath = Join-Path $ProjectDir 'notify-handler.ps1'
$ConfigPath = Join-Path $ProjectDir 'notify-config.json'
$SettingsPath = Join-Path $UserClaudeDir 'settings.json'
$BackupDir = Join-Path $UserClaudeDir 'backups'
$ShortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\ClaudeCodeNotify"

foreach ($d in @($ProjectDir, $BackupDir, $ShortcutDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Write-Host '=== Claude Code Windows Notification Installer ===' -ForegroundColor Cyan
Write-Host ''

# ===================================================================
# 1. Start Menu shortcut with AppUserModelID for WinRT toast
# ===================================================================
Write-Host '[1/5] Creating Start Menu shortcut with AUMID...' -ForegroundColor Yellow

$shortcutLnk = Join-Path $ShortcutDir 'claude-notify.lnk'
$AUMID = 'ClaudeCode.Toast'

# Inline C# to create .lnk with AppUserModelID via IShellLinkW + IPropertyStore
$csharpShortcut = @'
using System;
using System.Runtime.InteropServices;
using System.Text;

[ComImport, Guid("00021401-0000-0000-C000-000000000046")]
public class CShellLink { }

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("000214F9-0000-0000-C000-000000000046")]
public interface IShellLinkW {
    void GetPath([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszFile, int cchMaxPath, out IntPtr pfd, uint fFlags);
    IntPtr GetIDList();
    void SetIDList(IntPtr pidl);
    void GetDescription([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszName, int cchMaxName);
    void SetDescription([MarshalAs(UnmanagedType.LPWStr)] string pszName);
    void GetWorkingDirectory([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszDir, int cchMaxDir);
    void SetWorkingDirectory([MarshalAs(UnmanagedType.LPWStr)] string pszDir);
    void GetArguments([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszArgs, int cchMaxArgs);
    void SetArguments([MarshalAs(UnmanagedType.LPWStr)] string pszArgs);
    void GetHotkey(out ushort pwHotkey);
    void SetHotkey(ushort wHotkey);
    void GetShowCmd(out int piShowCmd);
    void SetShowCmd(int iShowCmd);
    void GetIconLocation([Out, MarshalAs(UnmanagedType.LPWStr)] StringBuilder pszIconPath, int cchIconPath, out int piIcon);
    void SetIconLocation([MarshalAs(UnmanagedType.LPWStr)] string pszIconPath, int iIcon);
    void SetRelativePath([MarshalAs(UnmanagedType.LPWStr)] string pszPathRel, uint dwReserved);
    void Resolve(IntPtr hwnd, uint fFlags);
    void SetPath([MarshalAs(UnmanagedType.LPWStr)] string pszFile);
}

[ComImport, InterfaceType(ComInterfaceType.InterfaceIsIUnknown), Guid("886D8EEB-8CF2-4446-8D02-CDBA1DBDCF99")]
public interface IPropertyStore {
    [PreserveSig] int GetCount(out uint cProps);
    [PreserveSig] int GetAt(uint iProp, out PropertyKey pkey);
    [PreserveSig] int GetValue(ref PropertyKey key, out object pv);
    [PreserveSig] int SetValue(ref PropertyKey key, object pv);
    [PreserveSig] int Commit();
}

[StructLayout(LayoutKind.Sequential, Pack = 4)]
public struct PropertyKey {
    public Guid fmtid;
    public uint pid;
}

public static class ShortcutBuilder {
    public static void Create(string lnkPath, string targetPath, string iconPath, string aumid, string desc) {
        var sl = (IShellLinkW)new CShellLink();
        sl.SetPath(targetPath);
        sl.SetDescription(desc);
        sl.SetShowCmd(1);
        sl.SetIconLocation(iconPath, 0);
        var ps = (IPropertyStore)sl;
        var key = new PropertyKey {
            fmtid = new Guid("9F4C2855-9F79-4B39-A8D0-E1D42DE1D5F3"),
            pid = 5
        };
        object val = aumid;
        int hr = ps.SetValue(ref key, val);
        if (hr < 0) {
            throw new InvalidOperationException(
                string.Format("SetValue HRESULT: 0x{0:X8}", hr));
        }
        hr = ps.Commit();
        if (hr < 0) {
            throw new InvalidOperationException(
                string.Format("Commit HRESULT: 0x{0:X8}", hr));
        }
        var pf = (System.Runtime.InteropServices.ComTypes.IPersistFile)sl;
        pf.Save(lnkPath, false);
    }
}
'@

$shortcutOk = $false
try {
    Add-Type -TypeDefinition $csharpShortcut -ErrorAction Stop
    [ShortcutBuilder]::Create($shortcutLnk, 'powershell.exe', "$env:USERPROFILE\claude-code-toast\ClaudeCode-logo.ico", $AUMID, 'Claude Code Notification Launcher')
    Write-Host "  Shortcut created with AUMID: $AUMID" -ForegroundColor Green
    Write-Host "  Path: $shortcutLnk" -ForegroundColor Green
    $shortcutOk = $true
} catch {
    Write-Host "  C# shortcut failed: $_" -ForegroundColor DarkYellow
    Write-Host "  Trying WScript.Shell fallback (no AUMID)..." -ForegroundColor DarkYellow
    try {
        $ws = New-Object -ComObject WScript.Shell
        $sc = $ws.CreateShortcut($shortcutLnk)
        $sc.TargetPath = 'powershell.exe'
        $sc.Description = 'Claude Code Notify Launcher'
        $sc.Save()
        Write-Host "  Fallback shortcut created: $shortcutLnk" -ForegroundColor DarkYellow
        $shortcutOk = $true
    } catch {
        Write-Host "  No shortcut created. Toast may use fallback identity." -ForegroundColor DarkYellow
    }
}

Write-Host ''

# ===================================================================
# 2. Verify handler exists in project dir
# ===================================================================
Write-Host '[2/4] Verifying handler script...' -ForegroundColor Yellow

if (Test-Path $HandlerPath) {
    Write-Host "  Handler present: $HandlerPath" -ForegroundColor Green
} else {
    Write-Error "Handler script not found at $HandlerPath"
    exit 1
}

Write-Host ''

# ===================================================================
# 3. Config
# ===================================================================
Write-Host '[3/4] Checking notification config...' -ForegroundColor Yellow

if (-not (Test-Path $ConfigPath)) {
    $defaultConfig = [PSCustomObject]@{
        enableToast    = $true
        enableSound    = $true
        quietHours     = [PSCustomObject]@{ enabled = $false; start = "22:00"; end = "08:00" }
        minSeverity    = 'low'
        dedupeSeconds  = 5
        showCwd        = $true
        showSummary    = $true
        summaryMaxChars = 150
        debugLog       = $false
        events         = [PSCustomObject]@{
            'Stop'                       = [PSCustomObject]@{ enabled = $true; severity = 'low' }
            'StopFailure'                = [PSCustomObject]@{ enabled = $true; severity = 'high' }
            'Notification'               = [PSCustomObject]@{ enabled = $true; severity = 'medium' }
            'PermissionRequest'          = [PSCustomObject]@{ enabled = $true; severity = 'high' }
            'PreToolUse:AskUserQuestion' = [PSCustomObject]@{ enabled = $true; severity = 'high' }
            'PreToolUse:ExitPlanMode'    = [PSCustomObject]@{ enabled = $true; severity = 'high' }
            'SubagentStop'               = [PSCustomObject]@{ enabled = $true; severity = 'low' }
            'TaskCompleted'              = [PSCustomObject]@{ enabled = $true; severity = 'low' }
            'SessionStart'               = [PSCustomObject]@{ enabled = $false; severity = 'low' }
            'SessionEnd'                 = [PSCustomObject]@{ enabled = $false; severity = 'low' }
        }
    }
    $defaultConfig | ConvertTo-Json -Depth 4 | Out-File -FilePath $ConfigPath -Encoding UTF8
    Write-Host "  Default config created: $ConfigPath" -ForegroundColor Green
} else {
    Write-Host "  Config already exists: $ConfigPath (left unchanged)" -ForegroundColor Green
}

Write-Host ''

# ===================================================================
# 4. Backup
# ===================================================================
Write-Host '[4/4] Backing up settings.json...' -ForegroundColor Yellow

if (Test-Path $SettingsPath) {
    $ts = Get-Date -Format 'yyyyMMdd-HHmmss'
    $backupPath = Join-Path $BackupDir "settings.json.before-notify.$ts"
    Copy-Item $SettingsPath $backupPath -Force
    Write-Host "  Backup saved: $backupPath" -ForegroundColor Green
} else {
    Write-Host "  No existing settings.json to back up" -ForegroundColor DarkYellow
}

Write-Host ''

# ===================================================================
# 5. Merge hooks
# ===================================================================
Write-Host '[5/5] Merging hooks into settings.json...' -ForegroundColor Yellow

# Read settings.json
if (Test-Path $SettingsPath) {
    try {
        $raw = Get-Content -Raw $SettingsPath -ErrorAction Stop
        if ([string]::IsNullOrWhiteSpace($raw)) {
            $settings = [PSCustomObject]@{}
        } else {
            $settings = $raw | ConvertFrom-Json
        }
    } catch {
        Write-Error "Failed to parse settings.json: $_"
        exit 1
    }
} else {
    $settings = [PSCustomObject]@{}
}

# Ensure hooks property
if (-not ($settings.PSObject.Properties.Name -contains 'hooks')) {
    $settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue ([PSCustomObject]@{})
}

# Handler command
$handlerCmd = "powershell -NoProfile -ExecutionPolicy Bypass -File `"$($HandlerPath -replace '\\','/')`""
$handlerObj = [PSCustomObject]@{ type = 'command'; command = $handlerCmd }

# Copy existing hooks into a regular hashtable (use .ContainsKey which works on System.Collections.Hashtable)
$hooksHT = @{}
foreach ($prop in $settings.hooks.PSObject.Properties) {
    $hooksHT[$prop.Name] = $prop.Value
}

# Helper: check if our handler already exists for a matcher
function Test-HandlerPresent {
    param($Matchers, $TargetMatcher)
    if ($null -eq $Matchers) { return $false }
    # Ensure array
    $arr = @($Matchers)
    foreach ($m in $arr) {
        $mMatcher = if ($m -is [PSCustomObject]) { $m.matcher } else { '' }
        if ($mMatcher -ne $TargetMatcher) { continue }
        $hks = if ($m -is [PSCustomObject]) { $m.hooks } else { $null }
        if ($hks) {
            foreach ($h in @($hks)) {
                $hkCmd = if ($h -is [PSCustomObject]) { $h.command } else { '' }
                if ($hkCmd -eq $handlerCmd) { return $true }
            }
        }
    }
    return $false
}

$addedCount = 0
$skippedCount = 0

# Standard events
$neededEvents = [ordered]@{
    'Stop'              = 'Task completed'
    'StopFailure'       = 'Task failed'
    'Notification'      = 'Waiting for input'
    'PermissionRequest' = 'Permission required'
    'SubagentStop'      = 'Subagent completed'
    'TaskCompleted'     = 'Team task completed'
}

foreach ($eventName in $neededEvents.Keys) {
    $existing = if ($hooksHT.ContainsKey($eventName)) { $hooksHT[$eventName] } else { @() }
    if (Test-HandlerPresent $existing '') {
        Write-Host "  [$eventName] handler already exists - skipped" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }
    $entry = [PSCustomObject]@{ matcher = ''; hooks = @($handlerObj) }
    if ($hooksHT.ContainsKey($eventName)) {
        $hooksHT[$eventName] = @($hooksHT[$eventName]) + $entry
    } else {
        $hooksHT[$eventName] = @($entry)
    }
    Write-Host "  [$eventName] handler added ($($neededEvents[$eventName]))" -ForegroundColor Green
    $addedCount++
}

# PreToolUse events
$ptuEvents = @(
    [PSCustomObject]@{ matcher = 'AskUserQuestion'; label = 'Claude asks question' },
    [PSCustomObject]@{ matcher = 'ExitPlanMode';    label = 'Plan ready for review' }
)
foreach ($ptu in $ptuEvents) {
    $existing = if ($hooksHT.ContainsKey('PreToolUse')) { $hooksHT['PreToolUse'] } else { @() }
    if (Test-HandlerPresent $existing $ptu.matcher) {
        Write-Host "  [PreToolUse:$($ptu.matcher)] handler already exists - skipped" -ForegroundColor DarkGray
        $skippedCount++
        continue
    }
    $entry = [PSCustomObject]@{ matcher = $ptu.matcher; hooks = @($handlerObj) }
    if ($hooksHT.ContainsKey('PreToolUse')) {
        $hooksHT['PreToolUse'] = @($hooksHT['PreToolUse']) + $entry
    } else {
        $hooksHT['PreToolUse'] = @($entry)
    }
    Write-Host "  [PreToolUse:$($ptu.matcher)] handler added ($($ptu.label))" -ForegroundColor Green
    $addedCount++
}

# Write back: use a regular PSCustomObject for hooks (not [ordered] to avoid PS 5.1 issues)
$hooksObj = [PSCustomObject]$hooksHT
$settings.PSObject.Properties.Remove('hooks')
$settings | Add-Member -NotePropertyName 'hooks' -NotePropertyValue $hooksObj

# Serialize
$finalJson = $settings | ConvertTo-Json -Depth 10
$finalJson | Out-File -FilePath $SettingsPath -Encoding UTF8

Write-Host ''
Write-Host "=== Installation Complete ===" -ForegroundColor Cyan
Write-Host "  Events added:    $addedCount" -ForegroundColor Green
Write-Host "  Skipped (dupes): $skippedCount" -ForegroundColor DarkGray
Write-Host "  Config:          $ConfigPath" -ForegroundColor Green
Write-Host "  Settings:        $SettingsPath" -ForegroundColor Green
Write-Host "  Handler:         $HandlerPath" -ForegroundColor Green
if ($shortcutOk) {
    Write-Host "  Shortcut:        $shortcutLnk" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Next steps:' -ForegroundColor White
Write-Host '  1. Run  /hooks  in Claude Code to verify hooks are configured' -ForegroundColor White
Write-Host '  2. Test with a simple task and verify notifications appear' -ForegroundColor White
Write-Host '  3. Edit  ~/.claude/notify-config.json  to adjust per-event settings' -ForegroundColor White
Write-Host '  4. To uninstall, run: uninstall-notify.ps1' -ForegroundColor White
Write-Host ''
