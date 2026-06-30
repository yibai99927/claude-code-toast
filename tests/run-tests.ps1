#Requires -Version 5.1
$ErrorActionPreference = 'Stop'

$Root = Split-Path $PSScriptRoot -Parent
$Lib  = Join-Path $Root 'lib'
$Passed = 0
$Failed = 0

function Assert-True {
    param([bool]$Condition, [string]$Name)
    if ($Condition) {
        Write-Host "PASS $Name" -ForegroundColor Green
        $script:Passed++
    } else {
        Write-Host "FAIL $Name" -ForegroundColor Red
        $script:Failed++
    }
}

. (Join-Path $Lib 'version.ps1')
. (Join-Path $Lib 'config.ps1')
. (Join-Path $Lib 'dedup.ps1')
. (Join-Path $Lib 'classifier.ps1')
. (Join-Path $Lib 'messages.ps1')
. (Join-Path $Lib 'webhooks.ps1')

Assert-True ((Get-PluginVersion $Root) -eq '1.2.0') 'plugin version from plugin.json'

Assert-True ((Get-NotifyType 'Stop' '') -eq 'task_done') 'Get-NotifyType Stop'
Assert-True ($null -eq (Get-NotifyType 'PreToolUse' 'Bash')) 'Get-NotifyType unknown tool'
Assert-True ((Get-EventConfigKey 'PreToolUse' 'AskUserQuestion') -eq 'PreToolUse:AskUserQuestion') 'event config key'

Assert-True (Test-SeverityGate 'high' 'low') 'severity gate high vs low'
Assert-True (-not (Test-SeverityGate 'low' 'high')) 'severity gate low vs high'

$qh = @{ enabled = $true; start = '22:00'; end = '08:00' }
Assert-True ($null -ne (Get-Command Test-QuietHours)) 'quiet hours function exists'

$merged = Merge-EventConfig @{ 'Stop' = @{ enabled = $false } }
Assert-True ($merged.Stop.enabled -eq $false) 'deep merge events override'
Assert-True ($merged.StopFailure.enabled -eq $true) 'deep merge events preserve defaults'

$payload = [PSCustomObject]@{ teammate_name = 'worker-1'; task_subject = 'ignored' }
$key1 = Get-DedupKey -SessionId 's1' -NotifyType 'subtask_done' -ToolName '' -Payload $payload
$key2 = Get-DedupKey -SessionId 's1' -NotifyType 'subtask_done' -ToolName '' -Payload $payload
Assert-True ($key1 -eq $key2) 'subtask dedup key stable'
Assert-True ($key1 -like '*subtask_done*worker-1*') 'subtask dedup key uses teammate'

Assert-True (Test-WebhookUrl 'https://example.com/hook') 'valid webhook url'
Assert-True (-not (Test-WebhookUrl 'file:///etc/passwd')) 'reject file url'
Assert-True (-not (Test-WebhookUrl '')) 'reject empty url'

$long = 'x' * 5000
$trim = Limit-WebhookText $long 'telegram'
Assert-True ($trim.Length -le 4096) 'telegram length limit'

$cfg = Get-DefaultNotifyConfig
$msg = Build-NotificationMessage 'task_done' ([PSCustomObject]@{ cwd = 'C:\dev\proj'; last_assistant_message = 'hello' }) $cfg
Assert-True ($msg.Title -like '*') 'build task_done message'
Assert-True ($msg.ProjectPath -eq 'C:\dev\proj') 'message includes project path'

$ev = Get-EventConfig $cfg 'Stop' 'Stop'
Assert-True ((Get-ConfigValue $ev 'respectQuietHours' $null) -eq $true) 'default respectQuietHours'

Write-Host ''
Write-Host "Results: $Passed passed, $Failed failed"
if ($Failed -gt 0) { exit 1 }
exit 0
