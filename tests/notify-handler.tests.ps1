param(
    [string]$HandlerPath = (Join-Path $PSScriptRoot '..\notify-handler.ps1')
)

$ErrorActionPreference = 'Stop'
$HandlerPath = (Resolve-Path $HandlerPath).Path
$originalUserProfile = $env:USERPROFILE
$tempProfile = Join-Path ([System.IO.Path]::GetTempPath()) ("claude-code-toast-test-" + [guid]::NewGuid())
$dataDir = Join-Path $tempProfile '.claude\claude-code-toast'
$logPath = Join-Path $dataDir 'logs\notify.log'
$configPath = Join-Path $dataDir 'notify-config.json'
$failures = @()

function Invoke-TestPayload {
    param([hashtable]$Payload)

    $json = $Payload | ConvertTo-Json -Compress
    $json | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $HandlerPath -ConfigPath $configPath
    if ($LASTEXITCODE -ne 0) {
        throw "Handler exited with code $LASTEXITCODE"
    }
}

try {
    New-Item -ItemType Directory -Path $dataDir -Force | Out-Null
    New-Item -ItemType File -Path (Join-Path $dataDir '.setup-done') -Force | Out-Null
    @{
        enableToast = $false
        enableSound = $false
        minSeverity = 'low'
        showCwd = $false
        showSummary = $false
        events = @{
            Stop = @{ enabled = $true; severity = 'low' }
        }
    } | ConvertTo-Json -Depth 4 | Set-Content -Path $configPath -Encoding UTF8

    $env:USERPROFILE = $tempProfile

    Invoke-TestPayload @{
        hook_event_name = 'stop'
        session_id = 'cursor-regression'
        cursor_version = '3.11.13'
    }

    if (Test-Path $logPath) {
        $failures += 'Cursor hook payload must be ignored without writing a notification log.'
        Remove-Item $logPath -Force
    }

    Invoke-TestPayload @{
        hook_event_name = 'Stop'
        session_id = 'claude-regression'
    }

    if (-not (Test-Path $logPath)) {
        $failures += 'Claude Code hook payload must still be processed.'
    } else {
        $log = Get-Content $logPath -Raw
        if ($log -notmatch 'session=claude-regression') {
            $failures += 'Claude Code hook payload was not recorded as processed.'
        }
    }

    if ($failures.Count -gt 0) {
        throw ($failures -join [Environment]::NewLine)
    }

    Write-Host 'PASS: Cursor payload ignored; Claude Code payload preserved.'
} finally {
    $env:USERPROFILE = $originalUserProfile
    Remove-Item $tempProfile -Recurse -Force -ErrorAction SilentlyContinue
}
