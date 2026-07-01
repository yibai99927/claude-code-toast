function Read-StdinJson {
    $raw = $null
    try {
        $prevEnc = [Console]::InputEncoding
        [Console]::InputEncoding = [Text.Encoding]::UTF8
        $raw = [System.Console]::In.ReadToEnd()
        [Console]::InputEncoding = $prevEnc
    } catch { }
    if ([string]::IsNullOrWhiteSpace($raw)) {
        try { $raw = ($input | Out-String) } catch { }
    }
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    $raw = $raw.Trim()
    if ($raw.Length -eq 0) { return $null }
    try { return $raw | ConvertFrom-Json } catch { return $null }
}

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

function Get-EventConfigKey {
    param($EventName, $ToolName)
    if ($EventName -eq 'PreToolUse' -and $ToolName) {
        return "PreToolUse:$ToolName"
    }
    return $EventName
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

function Test-QuietHours {
    param($QuietHoursConfig)
    if (-not $QuietHoursConfig.enabled) { return $false }
    try {
        $now = Get-Date
        $start = [datetime]::ParseExact($QuietHoursConfig.start, 'HH:mm', $null)
        $end   = [datetime]::ParseExact($QuietHoursConfig.end, 'HH:mm', $null)
        if ($start -le $end) {
            return ($now.TimeOfDay -ge $start.TimeOfDay -and $now.TimeOfDay -le $end.TimeOfDay)
        }
        return ($now.TimeOfDay -ge $start.TimeOfDay -or $now.TimeOfDay -le $end.TimeOfDay)
    } catch { return $false }
}

function Test-ShouldSuppressQuietHours {
    param($EventCfg, $EventSeverity)
    $sevRank = Get-SeverityRank $EventSeverity
    if ($sevRank -ge 2) { return $false }
    $respect = Get-ConfigValue $EventCfg 'respectQuietHours' $true
    if ($respect -eq $false) { return $false }
    return $true
}
