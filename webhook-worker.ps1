#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)][string]$PayloadFile,
    [Parameter(Mandatory = $true)][string]$PluginRoot
)

$ErrorActionPreference = 'Continue'
$LibDir = Join-Path $PluginRoot 'lib'
. (Join-Path $LibDir 'logging.ps1')
. (Join-Path $LibDir 'config.ps1')
. (Join-Path $LibDir 'webhooks.ps1')

try {
    if (-not (Test-Path $PayloadFile)) { exit 0 }
    $data = Get-Content -Raw $PayloadFile | ConvertFrom-Json
    $config = @{ webhooks = Merge-WebhookConfig $data.webhooks }
    Send-WebhooksSync -EventKey $data.eventKey -Title $data.title -Body $data.body -CwdName $data.cwdName -Config $config
} catch {
    Write-NotifyLog "Webhook worker failed: $_" -Level 'WARN'
} finally {
    Remove-Item $PayloadFile -Force -ErrorAction SilentlyContinue
}

exit 0
