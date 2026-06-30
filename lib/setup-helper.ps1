function Get-SetupStatusPath {
    return "$env:USERPROFILE\.claude\claude-code-toast\.setup-status.json"
}

function Get-SetupMarkerPath {
    return "$env:USERPROFILE\.claude\claude-code-toast\.setup-done"
}

function Read-SetupStatus {
    $path = Get-SetupStatusPath
    if (-not (Test-Path $path)) { return $null }
    try { return Get-Content -Raw $path | ConvertFrom-Json } catch { return $null }
}

function Invoke-ShortcutRetry {
    param([string]$PluginRoot)
    $setupScript = Join-Path $PluginRoot 'setup.ps1'
    if (-not (Test-Path $setupScript)) { return }
    try {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript -ShortcutOnly 2>&1 | Out-Null
    } catch { }
}

function Invoke-AutoSetup {
    param([string]$PluginRoot)

    $markerFile = Get-SetupMarkerPath
    $configPath = "$env:USERPROFILE\.claude\claude-code-toast\notify-config.json"
    $status = Read-SetupStatus

    if (Test-Path $markerFile) {
        if ($status -and ($status.shortcutOk -eq $false)) {
            Write-NotifyLog 'Auto-setup: retrying shortcut creation' -Level 'INFO'
            Invoke-ShortcutRetry $PluginRoot
        }
        return
    }

    $setupScript = Join-Path $PluginRoot 'setup.ps1'
    if (-not (Test-Path $setupScript)) {
        Write-NotifyLog "Auto-setup: setup.ps1 not found at $setupScript" -Level 'WARN'
        return
    }

    try {
        Write-NotifyLog 'Auto-setup: running first-time Windows setup...' -Level 'INFO'
        $setupOutput = & powershell -NoProfile -ExecutionPolicy Bypass -File $setupScript 2>&1
        $setupExitCode = $LASTEXITCODE
        $setupLogDir = "$env:USERPROFILE\.claude\claude-code-toast\logs"
        if (-not (Test-Path $setupLogDir)) { New-Item -ItemType Directory -Path $setupLogDir -Force | Out-Null }
        $setupOutput | Out-File -FilePath (Join-Path $setupLogDir 'setup.log') -Encoding UTF8

        $status = Read-SetupStatus
        if ($setupExitCode -ne 0 -and -not (Test-Path $configPath)) {
            Write-NotifyLog "Auto-setup: setup.ps1 exited with code $setupExitCode — will retry on next hook" -Level 'WARN'
            return
        }

        if ((Test-Path $configPath) -or ($status -and $status.configOk)) {
            '' | Out-File -FilePath $markerFile -Encoding UTF8
            Write-NotifyLog 'Auto-setup: completed — config initialized' -Level 'INFO'
        }
        if ($status -and ($status.shortcutOk -eq $false)) {
            Write-NotifyLog 'Auto-setup: shortcut missing — will retry on next hook' -Level 'WARN'
        }
    } catch {
        Write-NotifyLog "Auto-setup: failed — $_" -Level 'WARN'
    }
}
