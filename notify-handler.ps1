#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Code Windows notification handler.
  Reads hook JSON from stdin, classifies the event, and shows a Windows toast/sound.
.DESCRIPTION
  Called by Claude Code hooks. All events route through this single script.
  Toast (WinRT) -> NotifyIcon balloon -> system sound fallback chain.
  Dedup, quiet hours, per-event enable/disable all read from ~/.claude/notify-config.json.
#>
param(
    [string]$ConfigPath = "$env:USERPROFILE\claude-code-notify\notify-config.json",
    [string]$LogDir = "$env:USERPROFILE\claude-code-notify\logs"
)

$ErrorActionPreference = 'Continue'
$script:HandlerVersion = '1.0.0'

# =================================================================== helpers

function Read-StdinJson {
    $raw = $null
    try { $raw = [System.Console]::In.ReadToEnd() } catch { }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        try { $raw = ($input | Out-String) } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $raw = $raw.Trim()
    if ($raw.Length -eq 0) { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

function Load-NotifyConfig {
    param([string]$Path)
    $defaults = @{
        enableToast    = $true
        enableSound    = $true
        quietHours     = @{ enabled = $false; start = "22:00"; end = "08:00" }
        minSeverity    = 'low'
        dedupeSeconds  = 5
        showCwd        = $true
        showSummary    = $true
        summaryMaxChars = 150
        debugLog       = $false
        events         = @{}
    }
    if (-not (Test-Path $Path)) { return $defaults }
    try {
        $user = Get-Content -Raw $Path | ConvertFrom-Json
        $merged = @{}
        foreach ($k in $defaults.Keys) {
            $merged[$k] = if ($user.PSObject.Properties.Name -contains $k) { $user.$k } else { $defaults[$k] }
        }
        return $merged
    } catch { return $defaults }
}

function Write-NotifyLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO'
    )
    $logDir = "$env:USERPROFILE\claude-code-notify\logs"
    if (-not (Test-Path $logDir)) {
        try { New-Item -ItemType Directory -Path $logDir -Force | Out-Null } catch { return }
    }
    $logFile = Join-Path $logDir 'notify.log'
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "$ts [$Level] $Message"
    try {
        if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
            $rotated = Join-Path $logDir ('notify.{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
            Move-Item $logFile $rotated -Force
        }
        $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    } catch { }
}

function Test-QuietHours {
    param($QuietHoursConfig)
    if (-not $QuietHoursConfig.enabled) { return $false }
    try {
        $now = Get-Date
        $start = [datetime]::ParseExact($QuietHoursConfig.start, 'HH:mm', $null)
        $end   = [datetime]::ParseExact($QuietHoursConfig.end, 'HH:mm', $null)
        if ($start -le $end) {
            return ($now.TimeOfDay -ge $start.TimeOfDay -and $now.TimeOfDay -le $end.TimeOfDay)
        } else {
            return ($now.TimeOfDay -ge $start.TimeOfDay -or $now.TimeOfDay -le $end.TimeOfDay)
        }
    } catch { return $false }
}

# -------- dedup cache (in-memory, process lifetime) --------
$script:DedupCache = @{}

function Test-Dedup {
    param([string]$Key, [int]$WindowSeconds)
    $now = Get-Date
    if ($script:DedupCache.ContainsKey($Key)) {
        $elapsed = ($now - $script:DedupCache[$Key]).TotalSeconds
        if ($elapsed -lt $WindowSeconds) { return $true }
    }
    $script:DedupCache[$Key] = $now
    $stale = @($script:DedupCache.Keys | Where-Object { ($now - $script:DedupCache[$_]).TotalSeconds -gt 300 })
    foreach ($k in $stale) { $script:DedupCache.Remove($k) }
    return $false
}

# -------- classification --------

function Get-NotifyType {
    param($EventName, $ToolName)
    switch ($EventName) {
        'Stop'              { return 'task_done' }
        'StopFailure'       { return 'failed' }
        'Notification'      { return 'needs_input' }
        'PermissionRequest' { return 'permission_required' }
        'PreToolUse' {
            if ($ToolName -eq 'AskUserQuestion') { return 'question' }
            if ($ToolName -eq 'ExitPlanMode')    { return 'plan_ready' }
            return $null
        }
        'SubagentStop'  { return 'subtask_done' }
        'TaskCompleted' { return 'subtask_done' }
        'SessionStart'  { return 'session' }
        'SessionEnd'    { return 'session' }
        default         { return $null }
    }
}

function Get-SeverityRank {
    param([string]$Severity)
    switch ($Severity) {
        'low'    { return 0 }
        'medium' { return 1 }
        'high'   { return 2 }
        default  { return 0 }
    }
}

function Test-SeverityGate {
    param($EventSeverity, $MinSeverity)
    $eventRank = Get-SeverityRank $EventSeverity
    $minRank   = Get-SeverityRank $MinSeverity
    return $eventRank -ge $minRank
}

# -------- message builders --------

function Get-WorkingDirName {
    param($PayloadCwd)
    if (-not $PayloadCwd) { return '' }
    try { return (Split-Path $PayloadCwd -Leaf) } catch { return $PayloadCwd }
}

function Get-SummaryPreview {
    param($Text, $MaxChars)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $Text = $Text.Trim()
    if ($Text.Length -le $MaxChars) { return $Text }
    return $Text.Substring(0, $MaxChars) + [char]0x2026  # ellipsis
}

function Build-NotificationMessage {
    param($Type, $Payload, $Config)
    $cwdName = if ($Config.showCwd) { Get-WorkingDirName $Payload.cwd } else { '' }
    $cwdLabel = if ($cwdName) { "Project: $cwdName — " } else { '' }

    switch ($Type) {
        'task_done' {
            $title = 'Claude Code — Task Complete'
            if ($Config.showSummary -and $Payload.last_assistant_message) {
                $body = Get-SummaryPreview $Payload.last_assistant_message $Config.summaryMaxChars
            } elseif ($cwdName) {
                $body = "Project: $cwdName — response finished"
            } else {
                $body = 'Claude finished the current response'
            }
            return @{ Title = $title; Body = $body; Sound = 'Asterisk'; ToastAudio = 'Default' }
        }
        'failed' {
            return @{
                Title = 'Claude Code — Execution Failed'
                Body  = "${cwdLabel}Claude stopped unexpectedly or encountered an error"
                Sound = 'Hand'; ToastAudio = 'Alarm'
            }
        }
        'needs_input' {
            $ntype = if ($Payload.notification_type) { " ($($Payload.notification_type))" } else { '' }
            return @{
                Title = 'Claude Code — Waiting for Input'
                Body  = "${cwdLabel}Claude is waiting for your reply${ntype}"
                Sound = 'Asterisk'; ToastAudio = 'IM'
            }
        }
        'permission_required' {
            $tool = if ($Payload.tool_name) { $Payload.tool_name } else { 'a tool' }
            $action = ''
            if ($Payload.tool_input) {
                $inp = $Payload.tool_input
                if ($inp -is [string]) {
                    $action = if ($inp.Length -gt 80) { $inp.Substring(0, 80) + [char]0x2026 } else { $inp }
                } else { $action = "$inp" }
            }
            $body = "${cwdLabel}Permission needed to run $tool"
            if ($action) { $body += "`n$action" }
            return @{ Title = 'Claude Code — Permission Required'; Body = $body; Sound = 'Exclamation'; ToastAudio = 'Reminder' }
        }
        'question' {
            return @{
                Title = 'Claude Code — Question'
                Body  = "${cwdLabel}Claude has a question for you"
                Sound = 'Question'; ToastAudio = 'Reminder'
            }
        }
        'plan_ready' {
            return @{
                Title = 'Claude Code — Plan Ready'
                Body  = "${cwdLabel}A plan is ready for your review"
                Sound = 'Exclamation'; ToastAudio = 'Reminder'
            }
        }
        'subtask_done' {
            $sub = if ($Payload.teammate_name) { $Payload.teammate_name }
                   elseif ($Payload.task_subject) { $Payload.task_subject }
                   else { '' }
            $body = if ($sub) { "Completed: $sub" } else { "${cwdLabel}Subtask / agent finished" }
            return @{ Title = 'Claude Code — Subtask Done'; Body = $body; Sound = 'Asterisk'; ToastAudio = 'Default' }
        }
        'session' {
            $verb = if ($Payload.hook_event_name -eq 'SessionStart') { 'Started' } else { 'Ended' }
            return @{
                Title = "Claude Code — Session $verb"
                Body  = if ($cwdName) { "Project: $cwdName" } else { '' }
                Sound = 'Asterisk'; ToastAudio = 'Default'
            }
        }
        default { return $null }
    }
}

# -------- toast backends --------

$script:WinRTAvailable = $null

function Test-WinRTAvailable {
    if ($null -ne $script:WinRTAvailable) { return $script:WinRTAvailable }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $script:WinRTAvailable = $true
        return $true
    } catch {
        $script:WinRTAvailable = $false
        return $false
    }
}

$script:ToastAumid = 'ClaudeCode.Notify'

function Send-WinRTToast {
    param($Title, $Body, [string]$Audio = 'Default')
    if (-not (Test-WinRTAvailable)) { return $false }
    try {
        $escTitle = Escape-Xml $Title
        $escBody  = Escape-Xml $Body
        $xmlStr = "<toast duration=`"short`"><visual><binding template=`"ToastGeneric`"><text>$escTitle</text><text>$escBody</text></binding></visual><audio src=`"ms-winsoundevent:Notification.$Audio`"/></toast>"
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlStr)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $toast.ExpirationTime = [DateTimeOffset]::Now.AddSeconds(30)

        $notifier = $null
        $aumids = @(
            $script:ToastAumid,
            'Microsoft.Windows.Explorer',
            '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        )
        foreach ($appId in $aumids) {
            try {
                $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
                break
            } catch { }
        }
        if ($null -eq $notifier) { return $false }
        $notifier.Show($toast)
        return $true
    } catch { return $false }
}

function Send-BalloonTip {
    param($Title, $Body, [string]$Sound = 'Asterisk')
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch { return $false }
    try {
        $icon = [System.Drawing.SystemIcons]::Information
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = $icon
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText  = $Body
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(8000)
        Start-Sleep -Milliseconds 500
        $notifyIcon.Dispose()
        return $true
    } catch { return $false }
}

function Play-NotifySound {
    param([string]$Sound)
    try {
        switch ($Sound) {
            'Asterisk'    { [System.Media.SystemSounds]::Asterisk.Play() }
            'Exclamation' { [System.Media.SystemSounds]::Exclamation.Play() }
            'Hand'        { [System.Media.SystemSounds]::Hand.Play() }
            'Question'    { [System.Media.SystemSounds]::Question.Play() }
        }
    } catch { }
}

function Escape-Xml {
    param([string]$Text)
    if (-not $Text) { return '' }
    $Text = $Text.Replace('&', '&amp;')
    $Text = $Text.Replace('"', '&quot;')
    $Text = $Text.Replace("'", '&apos;')
    $Text = $Text.Replace('<', '&lt;')
    $Text = $Text.Replace('>', '&gt;')
    return $Text
}

# -------- event config lookup --------

function Get-EventConfigKey {
    param($EventName, $ToolName)
    if ($EventName -eq 'PreToolUse' -and $ToolName) {
        return "PreToolUse:$ToolName"
    }
    return $EventName
}

# =================================================================== main

$Config = Load-NotifyConfig $ConfigPath

$Payload = Read-StdinJson
if ($null -eq $Payload) {
    Write-NotifyLog 'No valid JSON payload received from stdin' -Level 'WARN'
    exit 0
}

$EventName = $Payload.hook_event_name
$ToolName  = $Payload.tool_name
$SessionId = if ($Payload.session_id) { $Payload.session_id } else { 'unknown' }

if (-not $EventName) {
    Write-NotifyLog 'Payload missing hook_event_name' -Level 'WARN'
    if ($Config.debugLog) {
        try { Write-NotifyLog "Payload dump: $($Payload | ConvertTo-Json -Compress)" } catch { }
    }
    exit 0
}

$NotifyType = Get-NotifyType $EventName $ToolName
if ($null -eq $NotifyType) {
    Write-NotifyLog "Unhandled event: $EventName tool=$ToolName" -Level 'INFO'
    exit 0
}

# Per-event config lookup
$eventCfgKey = Get-EventConfigKey $EventName $ToolName
$eventCfg = $null
if ($Config.events -is [hashtable]) {
    if ($Config.events.ContainsKey($eventCfgKey)) { $eventCfg = $Config.events[$eventCfgKey] }
    elseif ($Config.events.ContainsKey($EventName)) { $eventCfg = $Config.events[$EventName] }
} elseif ($Config.events -is [PSCustomObject]) {
    try {
        if ($Config.events.PSObject.Properties.Name -contains $eventCfgKey) { $eventCfg = $Config.events.$eventCfgKey }
        elseif ($Config.events.PSObject.Properties.Name -contains $EventName) { $eventCfg = $Config.events.$EventName }
    } catch { }
}
if ($null -eq $eventCfg) { $eventCfg = @{ enabled = $true; severity = 'medium' } }

# Extract scalar values from config (handle both PSCustomObject and hashtable)
$evEnabled = if ($eventCfg -is [hashtable]) { $eventCfg['enabled'] } else { $eventCfg.enabled }
$evSeverity = if ($eventCfg -is [hashtable]) { $eventCfg['severity'] } else { $eventCfg.severity }
if ($null -eq $evEnabled) { $evEnabled = $true }
if ($null -eq $evSeverity) { $evSeverity = 'medium' }

if (-not $evEnabled) {
    Write-NotifyLog "Event suppressed by config: $eventCfgKey" -Level 'INFO'
    exit 0
}

# Severity gate
$sevRank = Get-SeverityRank $evSeverity
$minRank = Get-SeverityRank $Config.minSeverity
if ($sevRank -lt $minRank) {
    Write-NotifyLog "Event filtered by minSeverity: $eventCfgKey (sev=$evSeverity < min=$($Config.minSeverity))"
    exit 0
}

# Quiet hours (skip for high-severity events)
if ($sevRank -lt 2) {
    $qh = if ($Config.quietHours -is [hashtable]) { $Config.quietHours } else {
        @{ enabled = $Config.quietHours.enabled; start = $Config.quietHours.start; end = $Config.quietHours.end }
    }
    if (Test-QuietHours $qh) {
        Write-NotifyLog "Event suppressed by quiet hours: $eventCfgKey" -Level 'INFO'
        exit 0
    }
}

# Dedup
$dedupKey = "$SessionId`|$EventName`|$ToolName"
$dedupSec = if ($Config.dedupeSeconds -is [int]) { $Config.dedupeSeconds } else { 5 }
if (Test-Dedup $dedupKey $dedupSec) {
    Write-NotifyLog "Event suppressed by dedup: $dedupKey"
    exit 0
}

# Build message
$Msg = Build-NotificationMessage $NotifyType $Payload $Config
if ($null -eq $Msg) {
    Write-NotifyLog "No message built for type=$NotifyType" -Level 'WARN'
    exit 0
}

# Log event
$cwdLeaf = if ($Config.showCwd) { Get-WorkingDirName $Payload.cwd } else { '' }
$logMsg = "event=$EventName tool=$ToolName type=$NotifyType session=$SessionId"
if ($cwdLeaf) { $logMsg += " cwd=$cwdLeaf" }
Write-NotifyLog $logMsg -Level 'INFO'

if ($Config.debugLog) {
    try { Write-NotifyLog "DEBUG: $($Payload | ConvertTo-Json -Compress -Depth 3)" -Level 'DEBUG' } catch { }
}

# -------- deliver notification --------
# WinRT toast first (native Windows notification, custom AUMID)
# Balloon tip as fallback (system tray popup)
$toastOk = $false
$balloonOk = $false

$doToast = if ($Config.enableToast -is [bool]) { $Config.enableToast } else { $true }
$doSound = if ($Config.enableSound -is [bool]) { $Config.enableSound } else { $true }

if ($doToast) {
    $toastOk = Send-WinRTToast $Msg.Title $Msg.Body $Msg.ToastAudio
    if (-not $toastOk) {
        Write-NotifyLog 'WinRT toast failed, trying balloon fallback'
        $balloonOk = Send-BalloonTip $Msg.Title $Msg.Body $Msg.Sound
        if (-not $balloonOk) {
            Write-NotifyLog 'Both toast and balloon failed, console only'
            try {
                Write-Host "--- Claude Code Notification ---"
                Write-Host "$($Msg.Title)"
                Write-Host "$($Msg.Body)"
            } catch { }
        }
    }
}

if ($doSound) {
    Play-NotifySound $Msg.Sound
}

$delivery = if ($toastOk) { 'toast' } elseif ($balloonOk) { 'balloon' } else { 'console' }
Write-NotifyLog "Delivered via $delivery`| title=$($Msg.Title)" -Level 'INFO'

exit 0
