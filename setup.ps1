#Requires -Version 5.1
<#
.SYNOPSIS
  Post-install setup for claude-code-toast plugin.
  Creates Start Menu shortcut with AppUserModelID for WinRT toast identity,
  and initializes the user config file.
  Run this ONCE after /plugin install claude-code-toast@claude-code-toast.
.DESCRIPTION
  The plugin system handles hook registration automatically.
  This script only does Windows-specific one-time setup:
  1. Creates Start Menu shortcut with ClaudeCode.Toast AUMID
  2. Copies default config to ~/.claude/claude-code-toast/ if absent
#>

$ErrorActionPreference = 'Stop'
$UserClaudeDir = "$env:USERPROFILE\.claude"
$UserDataDir = Join-Path $UserClaudeDir 'claude-code-toast'
$ConfigPath = Join-Path $UserDataDir 'notify-config.json'
$IconPath = "$PSScriptRoot\ClaudeCode-logo.ico"
$ShortcutDir = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\claude-code-toast"

foreach ($d in @($UserDataDir, $ShortcutDir)) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Write-Host '=== claude-code-toast Setup ===' -ForegroundColor Cyan
Write-Host ''

# ===================================================================
# 1. Start Menu shortcut with AppUserModelID for WinRT toast
# ===================================================================
Write-Host '[1/2] Creating Start Menu shortcut with AUMID...' -ForegroundColor Yellow

$shortcutLnk = Join-Path $ShortcutDir 'claude-code-toast.lnk'
$AUMID = 'ClaudeCode.Toast'

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
    $icon = if (Test-Path $IconPath) { $IconPath } else { 'powershell.exe' }
    [ShortcutBuilder]::Create($shortcutLnk, 'powershell.exe', $icon, $AUMID, 'Claude Code Notification Launcher')
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
# 2. Initialize config
# ===================================================================
Write-Host '[2/2] Initializing notification config...' -ForegroundColor Yellow

if (-not (Test-Path $ConfigPath)) {
    $defaultConfig = [PSCustomObject]@{
        enableToast    = $true
        enableSound    = $true
        language       = 'zh-CN'
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
Write-Host '=== Setup Complete ===' -ForegroundColor Cyan
Write-Host ''
Write-Host 'Notifications are now active via the plugin system.' -ForegroundColor White
Write-Host "  Config: $ConfigPath" -ForegroundColor Green
if ($shortcutOk) {
    Write-Host "  Shortcut: $shortcutLnk" -ForegroundColor Green
}
Write-Host ''
Write-Host 'Manage the plugin:' -ForegroundColor White
Write-Host '  /plugin list               — verify claude-code-toast is enabled' -ForegroundColor White
Write-Host '  /plugin disable ...        — temporarily turn off notifications' -ForegroundColor White
Write-Host '  /plugin uninstall ...      — fully remove plugin + hooks' -ForegroundColor White
Write-Host ''
