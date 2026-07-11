$script:DedupCachePath = "$env:USERPROFILE\.claude\claude-code-toast\.dedup-cache.json"

function Get-DedupCachePath {
    return $script:DedupCachePath
}

function Read-DedupCache {
    param([string]$Path = $script:DedupCachePath)
    if (-not (Test-Path $Path)) { return @{} }
    try {
        $raw = Get-Content -Raw $Path
        if ([string]::IsNullOrWhiteSpace($raw)) { return @{} }
        $obj = $raw | ConvertFrom-Json
        $hash = @{}
        foreach ($prop in $obj.PSObject.Properties) {
            $hash[$prop.Name] = [double]$prop.Value
        }
        return $hash
    } catch {
        return @{}
    }
}

function Write-DedupCache {
    param(
        [hashtable]$Cache,
        [string]$Path = $script:DedupCachePath
    )
    $dir = Split-Path $Path -Parent
    if (-not (Test-Path $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $obj = New-Object PSObject
    foreach ($key in $Cache.Keys) {
        $obj | Add-Member -NotePropertyName $key -NotePropertyValue $Cache[$key] -Force
    }
    $obj | ConvertTo-Json -Compress | Out-File -FilePath $Path -Encoding UTF8 -Force
}

function Get-DedupKey {
    param(
        [string]$SessionId,
        [string]$NotifyType,
        [string]$ToolName,
        $Payload
    )
    $suffix = $ToolName
    if ($NotifyType -eq 'subtask_done') {
        $suffix = if ($Payload.teammate_name) { $Payload.teammate_name }
                  elseif ($Payload.task_subject) { $Payload.task_subject }
                  else { 'subtask' }
    }
    return "$SessionId|$NotifyType|$suffix"
}

function Test-Dedup {
    param(
        [string]$Key,
        [int]$WindowSeconds,
        [string]$CachePath = $script:DedupCachePath
    )
    $nowMs = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
    $cache = Read-DedupCache $CachePath

    $staleCutoff = $nowMs - (300 * 1000)
    $clean = @{}
    foreach ($k in $cache.Keys) {
        if ($cache[$k] -ge $staleCutoff) { $clean[$k] = $cache[$k] }
    }
    $cache = $clean

    if ($cache.ContainsKey($Key)) {
        $elapsedMs = $nowMs - $cache[$Key]
        if ($elapsedMs -lt ($WindowSeconds * 1000)) {
            return $true
        }
    }

    $cache[$Key] = $nowMs
    try {
        Write-DedupCache $cache $CachePath
    } catch { }
    return $false
}
