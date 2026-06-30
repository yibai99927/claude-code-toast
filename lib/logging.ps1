$script:NotifyLogDir = "$env:USERPROFILE\.claude\claude-code-toast\logs"

function Write-NotifyLog {
    param(
        [string]$Message,
        [string]$Level = 'INFO',
        [string]$LogDir = $script:NotifyLogDir
    )
    if (-not (Test-Path $LogDir)) {
        try { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null } catch { return }
    }
    $logFile = Join-Path $LogDir 'notify.log'
    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss.fff'
    $line = "$ts [$Level] $Message"
    try {
        if ((Test-Path $logFile) -and ((Get-Item $logFile).Length -gt 1MB)) {
            $rotated = Join-Path $LogDir ('notify.{0:yyyyMMdd-HHmmss}.log' -f (Get-Date))
            Move-Item $logFile $rotated -Force
        }
        $line | Out-File -FilePath $logFile -Append -Encoding UTF8
    } catch { }
}

function Get-SanitizedPayloadForLog {
    param($Payload)
    if ($null -eq $Payload) { return $null }
    try {
        $json = $Payload | ConvertTo-Json -Depth 6 -Compress
        $copy = $json | ConvertFrom-Json
        if ($copy.PSObject.Properties.Name -contains 'tool_input' -and $null -ne $copy.tool_input) {
            $ti = "$($copy.tool_input)"
            if ($ti.Length -gt 120) { $ti = $ti.Substring(0, 120) + '...' }
            $ti = $ti -replace '(?i)(password|token|secret|api[_-]?key|authorization)\s*[:=]\s*\S+', '$1=[REDACTED]'
            $copy.tool_input = $ti
        }
        return $copy
    } catch {
        return @{ note = 'payload serialization failed' }
    }
}
