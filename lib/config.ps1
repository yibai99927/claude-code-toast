function Get-DefaultNotifyConfig {
    return @{
        enableToast       = $true
        enableSound       = $true
        quietHours        = @{ enabled = $false; start = '22:00'; end = '08:00' }
        minSeverity       = 'low'
        dedupeSeconds     = 5
        showCwd           = $true
        showSummary       = $true
        summaryMaxChars   = 150
        debugLog          = $false
        language          = 'zh-CN'
        toastClickAction  = 'openFolder'
        events            = Get-DefaultEventConfig
        webhooks          = @{ enabled = $false; endpoints = @() }
    }
}

function Get-DefaultEventConfig {
    return @{
        'Stop'                       = @{ enabled = $true;  severity = 'low';    respectQuietHours = $true }
        'StopFailure'                = @{ enabled = $true;  severity = 'high';   respectQuietHours = $false }
        'Notification'               = @{ enabled = $true;  severity = 'medium'; respectQuietHours = $true }
        'PermissionRequest'          = @{ enabled = $true;  severity = 'high';   respectQuietHours = $false }
        'PreToolUse:AskUserQuestion' = @{ enabled = $true;  severity = 'high';   respectQuietHours = $false }
        'PreToolUse:ExitPlanMode'    = @{ enabled = $true;  severity = 'high';   respectQuietHours = $false }
        'SubagentStop'               = @{ enabled = $false; severity = 'low';    respectQuietHours = $true }
        'TaskCompleted'              = @{ enabled = $false; severity = 'low';    respectQuietHours = $true }
        'SessionStart'               = @{ enabled = $false; severity = 'low';    respectQuietHours = $true }
        'SessionEnd'                 = @{ enabled = $false; severity = 'low';    respectQuietHours = $true }
    }
}

function Merge-HashtableDeep {
    param(
        [hashtable]$Base,
        [hashtable]$Override
    )
    $result = @{}
    foreach ($key in $Base.Keys) {
        $result[$key] = $Base[$key]
    }
    if ($null -eq $Override) { return $result }
    foreach ($key in $Override.Keys) {
        $baseVal = $result[$key]
        $overVal = $Override[$key]
        if ($baseVal -is [hashtable] -and $overVal -is [hashtable]) {
            $result[$key] = Merge-HashtableDeep $baseVal $overVal
        } else {
            $result[$key] = $overVal
        }
    }
    return $result
}

function ConvertTo-Hashtable {
    param($InputObject)
    if ($null -eq $InputObject) { return @{} }
    if ($InputObject -is [hashtable]) { return $InputObject }
    $hash = @{}
    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($prop.Value -is [PSCustomObject]) {
            $hash[$prop.Name] = ConvertTo-Hashtable $prop.Value
        } elseif ($prop.Value -is [System.Array]) {
            $hash[$prop.Name] = @($prop.Value)
        } else {
            $hash[$prop.Name] = $prop.Value
        }
    }
    return $hash
}

function Merge-EventConfig {
    param($UserEvents)
    $defaults = Get-DefaultEventConfig
    if ($null -eq $UserEvents) { return $defaults }
    $userHash = ConvertTo-Hashtable $UserEvents
    return Merge-HashtableDeep $defaults $userHash
}

function Merge-WebhookConfig {
    param($UserWebhooks)
    $defaults = @{ enabled = $false; endpoints = @() }
    if ($null -eq $UserWebhooks) { return $defaults }
    $userHash = ConvertTo-Hashtable $UserWebhooks
    $merged = Merge-HashtableDeep $defaults $userHash
    if ($null -eq $merged['endpoints']) { $merged['endpoints'] = @() }
    return $merged
}

function Load-NotifyConfig {
    param([string]$Path)
    $defaults = Get-DefaultNotifyConfig
    if (-not (Test-Path $Path)) { return $defaults }
    try {
        $user = Get-Content -Raw $Path | ConvertFrom-Json
        $userHash = ConvertTo-Hashtable $user
        $merged = @{}
        foreach ($k in $defaults.Keys) {
            if ($k -eq 'events') {
                $merged[$k] = Merge-EventConfig $userHash['events']
            } elseif ($k -eq 'webhooks') {
                $merged[$k] = Merge-WebhookConfig $userHash['webhooks']
            } elseif ($userHash.ContainsKey($k)) {
                $merged[$k] = $userHash[$k]
            } else {
                $merged[$k] = $defaults[$k]
            }
        }
        if ($merged.quietHours -is [PSCustomObject]) {
            $merged.quietHours = ConvertTo-Hashtable $merged.quietHours
        }
        return $merged
    } catch {
        return $defaults
    }
}

function Get-EventConfig {
    param($Config, $EventCfgKey, $EventName)
    $eventCfg = $null
    $events = $Config.events
    if ($events -is [hashtable]) {
        if ($events.ContainsKey($EventCfgKey)) { $eventCfg = $events[$EventCfgKey] }
        elseif ($events.ContainsKey($EventName)) { $eventCfg = $events[$EventName] }
    }
    if ($null -eq $eventCfg) {
        $eventCfg = @{ enabled = $true; severity = 'medium'; respectQuietHours = $true }
    } elseif ($eventCfg -is [PSCustomObject]) {
        $eventCfg = ConvertTo-Hashtable $eventCfg
    }
    return $eventCfg
}

function Get-ConfigValue {
    param($Object, [string]$Key, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [hashtable]) {
        if ($Object.ContainsKey($Key)) { return $Object[$Key] }
        return $Default
    }
    if ($Object.PSObject.Properties.Name -contains $Key) { return $Object.$Key }
    return $Default
}
