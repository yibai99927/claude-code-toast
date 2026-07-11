#Requires -Version 5.1
<#
.SYNOPSIS
  Claude Code Windows notification handler (entry point).
.DESCRIPTION
  Loads lib/ modules and routes hook JSON to toast, sound, and webhook delivery.
#>
param(
    [string]$ConfigPath = "$env:USERPROFILE\.claude\claude-code-toast\notify-config.json"
)

$ErrorActionPreference = 'Continue'
$PluginRoot = $PSScriptRoot
$LibDir = Join-Path $PluginRoot 'lib'

. (Join-Path $LibDir 'version.ps1')
. (Join-Path $LibDir 'logging.ps1')
. (Join-Path $LibDir 'config.ps1')
. (Join-Path $LibDir 'dedup.ps1')
. (Join-Path $LibDir 'classifier.ps1')
. (Join-Path $LibDir 'messages.ps1')
. (Join-Path $LibDir 'toast.ps1')
. (Join-Path $LibDir 'webhooks.ps1')
. (Join-Path $LibDir 'setup-helper.ps1')

$script:HandlerVersion = Get-PluginVersion $PluginRoot

Invoke-AutoSetup -PluginRoot $PluginRoot

$Config = Load-NotifyConfig $ConfigPath
$Payload = Read-StdinJson

if ($null -eq $Payload) {
    Write-NotifyLog "v=$script:HandlerVersion No valid JSON payload received from stdin" -Level 'WARN'
    exit 0
}

# Cursor imports Claude Code plugins and adds this field to its hook payload.
# Let Cursor keep its native notifications instead of emitting a duplicate toast.
if ($Payload.PSObject.Properties.Name -contains 'cursor_version') {
    exit 0
}

$EventName = $Payload.hook_event_name
$ToolName  = $Payload.tool_name
$SessionId = if ($Payload.session_id) { $Payload.session_id } else { 'unknown' }

if (-not $EventName) {
    Write-NotifyLog "v=$script:HandlerVersion Payload missing hook_event_name" -Level 'WARN'
    if ($Config.debugLog) {
        try {
            $safe = Get-SanitizedPayloadForLog $Payload
            Write-NotifyLog "DEBUG: $($safe | ConvertTo-Json -Compress -Depth 3)" -Level 'DEBUG'
        } catch { }
    }
    exit 0
}

$NotifyType = Get-NotifyType $EventName $ToolName
if ($null -eq $NotifyType) {
    Write-NotifyLog "v=$script:HandlerVersion Unhandled event: $EventName tool=$ToolName" -Level 'INFO'
    exit 0
}

$eventCfgKey = Get-EventConfigKey $EventName $ToolName
$eventCfg = Get-EventConfig $Config $eventCfgKey $EventName

$evEnabled  = Get-ConfigValue $eventCfg 'enabled' $true
$evSeverity = Get-ConfigValue $eventCfg 'severity' 'medium'

if (-not $evEnabled) {
    Write-NotifyLog "v=$script:HandlerVersion Event suppressed by config: $eventCfgKey" -Level 'INFO'
    exit 0
}

if (-not (Test-SeverityGate $evSeverity $Config.minSeverity)) {
    Write-NotifyLog "v=$script:HandlerVersion Event filtered by minSeverity: $eventCfgKey (sev=$evSeverity < min=$($Config.minSeverity))"
    exit 0
}

if (Test-ShouldSuppressQuietHours $eventCfg $evSeverity) {
    $qh = $Config.quietHours
    if ($qh -is [PSCustomObject]) { $qh = ConvertTo-Hashtable $qh }
    if (Test-QuietHours $qh) {
        Write-NotifyLog "v=$script:HandlerVersion Event suppressed by quiet hours: $eventCfgKey" -Level 'INFO'
        exit 0
    }
}

$dedupKey = Get-DedupKey -SessionId $SessionId -NotifyType $NotifyType -ToolName $ToolName -Payload $Payload
$dedupSec = if ($Config.dedupeSeconds -is [int]) { $Config.dedupeSeconds } else { 5 }
if (Test-Dedup $dedupKey $dedupSec) {
    Write-NotifyLog "v=$script:HandlerVersion Event suppressed by dedup: $dedupKey"
    exit 0
}

$Msg = Build-NotificationMessage $NotifyType $Payload $Config
if ($null -eq $Msg) {
    Write-NotifyLog "v=$script:HandlerVersion No message built for type=$NotifyType" -Level 'WARN'
    exit 0
}

$cwdLeaf = if ($Config.showCwd) { Get-WorkingDirName $Payload.cwd } else { '' }
$logMsg = "v=$script:HandlerVersion event=$EventName tool=$ToolName type=$NotifyType session=$SessionId"
if ($cwdLeaf) { $logMsg += " cwd=$cwdLeaf" }
Write-NotifyLog $logMsg -Level 'INFO'

if ($Config.debugLog) {
    try {
        $safe = Get-SanitizedPayloadForLog $Payload
        Write-NotifyLog "DEBUG: $($safe | ConvertTo-Json -Compress -Depth 3)" -Level 'DEBUG'
    } catch { }
}

$delivery = Send-Notification -Msg $Msg -Config $Config -PluginRoot $PluginRoot
Write-NotifyLog "v=$script:HandlerVersion Delivered via $delivery| title=$($Msg.Title)" -Level 'INFO'

Send-WebhooksAsync -EventKey $eventCfgKey -Title $Msg.Title -Body $Msg.Body -CwdName $cwdLeaf -Config $Config -PluginRoot $PluginRoot

exit 0
