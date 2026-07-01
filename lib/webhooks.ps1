$script:WebhookMaxLength = @{
    telegram = 4096
    discord  = 2000
    wecom    = 2048
    feishu   = 30000
    dingtalk = 20000
    slack    = 40000
    qmsg     = 4000
    bark     = 4000
    pushplus = 20000
    http     = 4000
}

function Test-WebhookUrl {
    param([string]$Url)
    if ([string]::IsNullOrWhiteSpace($Url)) { return $false }
    try {
        $uri = [Uri]$Url
        if ($uri.Scheme -notin @('http', 'https')) { return $false }
        if ([string]::IsNullOrWhiteSpace($uri.Host)) { return $false }
        return $true
    } catch { return $false }
}

function Limit-WebhookText {
    param(
        [string]$Text,
        [string]$Type
    )
    if ([string]::IsNullOrEmpty($Text)) { return '' }
    $max = $script:WebhookMaxLength['http']
    if ($script:WebhookMaxLength.ContainsKey($Type)) {
        $max = $script:WebhookMaxLength[$Type]
    }
    if ($Text.Length -le $max) { return $Text }
    return $Text.Substring(0, [Math]::Max(0, $max - 1)) + [char]0x2026
}

function Get-EndpointValue {
    param($Endpoint, [string]$Key)
    return Get-ConfigValue $Endpoint $Key $null
}

function Invoke-WebhookRequest {
    param(
        [string]$Url,
        [string]$Body,
        [string]$ContentType = 'application/json; charset=utf-8'
    )
    Invoke-RestMethod -Uri $Url -Method Post -Body $Body -ContentType $ContentType -TimeoutSec 10 | Out-Null
}

function Send-SingleWebhook {
    param(
        $Endpoint,
        [string]$EventKey,
        [string]$Title,
        [string]$Body,
        [string]$CwdName
    )
    $epType = Get-EndpointValue $Endpoint 'type'
    $epUrl  = Get-EndpointValue $Endpoint 'url'
    $epName = Get-EndpointValue $Endpoint 'name'
    $epEvents = Get-EndpointValue $Endpoint 'events'

    if ($null -eq $epEvents -or ($EventKey -notin @($epEvents))) { return }
    if (-not (Test-WebhookUrl $epUrl)) {
        Write-NotifyLog "Webhook skipped ($epName): invalid URL" -Level 'WARN'
        return
    }

    $ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $textContent = "$Title`n$Body"
    if ($CwdName) { $textContent += "`nProject: $CwdName" }
    $textContent += "`n$ts"
    $textContent = Limit-WebhookText $textContent $epType

    try {
        switch ($epType) {
            'wecom' {
                $textPayload = @{ content = $textContent }
                $epAtAll = Get-EndpointValue $Endpoint 'at_all'
                $epMobiles = Get-EndpointValue $Endpoint 'at_mobiles'
                if ($epAtAll) {
                    $textPayload['mentioned_list'] = @('@all')
                } elseif ($null -ne $epMobiles -and @($epMobiles).Count -gt 0) {
                    $textPayload['mentioned_mobile_list'] = @($epMobiles)
                }
                $payload = @{ msgtype = 'text'; text = $textPayload } | ConvertTo-Json -Depth 3 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'telegram' {
                $payload = @{
                    chat_id = (Get-EndpointValue $Endpoint 'chat_id')
                    text    = $textContent
                } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'qmsg' {
                $payload = @{ msg = $textContent } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'discord' {
                $payload = @{ content = $textContent } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'slack' {
                $payload = @{ text = $textContent } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'feishu' {
                $payload = @{
                    msg_type = 'text'
                    content  = @{ text = $textContent }
                } | ConvertTo-Json -Depth 3 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'dingtalk' {
                $payload = @{
                    msgtype = 'text'
                    text    = @{ content = $textContent }
                } | ConvertTo-Json -Depth 3 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'bark' {
                $payload = @{
                    title = Limit-WebhookText $Title 'bark'
                    body  = Limit-WebhookText $Body 'bark'
                    group = (Get-EndpointValue $Endpoint 'group')
                } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'pushplus' {
                $token = Get-EndpointValue $Endpoint 'token'
                if ([string]::IsNullOrWhiteSpace($token)) {
                    Write-NotifyLog "Webhook skipped ($epName): pushplus token missing" -Level 'WARN'
                    return
                }
                $payload = @{
                    token   = $token
                    title   = Limit-WebhookText $Title 'pushplus'
                    content = $textContent
                } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            'http' {
                $payload = @{ content = $textContent } | ConvertTo-Json -Depth 2 -Compress
                Invoke-WebhookRequest $epUrl $payload
            }
            default {
                Write-NotifyLog "Unknown webhook type: $epType" -Level 'WARN'
                return
            }
        }
        Write-NotifyLog "Webhook sent: $epName ($epType)" -Level 'INFO'
    } catch {
        Write-NotifyLog "Webhook failed ($epName): $_" -Level 'WARN'
    }
}

function Send-WebhooksSync {
    param(
        [string]$EventKey,
        [string]$Title,
        [string]$Body,
        [string]$CwdName,
        $Config
    )
    $wh = $Config.webhooks
    if ($null -eq $wh) { return }
    $whEnabled = Get-ConfigValue $wh 'enabled' $false
    if (-not $whEnabled) { return }
    $endpoints = Get-ConfigValue $wh 'endpoints' @()
    if ($null -eq $endpoints -or @($endpoints).Count -eq 0) { return }

    foreach ($ep in @($endpoints)) {
        Send-SingleWebhook -Endpoint $ep -EventKey $EventKey -Title $Title -Body $Body -CwdName $CwdName
    }
}

function Send-WebhooksAsync {
    param(
        [string]$EventKey,
        [string]$Title,
        [string]$Body,
        [string]$CwdName,
        $Config,
        [string]$PluginRoot
    )
    $wh = $Config.webhooks
    if ($null -eq $wh) { return }
    $whEnabled = Get-ConfigValue $wh 'enabled' $false
    if (-not $whEnabled) { return }
    $endpoints = Get-ConfigValue $wh 'endpoints' @()
    if ($null -eq $endpoints -or @($endpoints).Count -eq 0) { return }

    $worker = Join-Path $PluginRoot 'webhook-worker.ps1'
    if (-not (Test-Path $worker)) {
        Send-WebhooksSync -EventKey $EventKey -Title $Title -Body $Body -CwdName $CwdName -Config $Config
        return
    }

    $payload = @{
        eventKey = $EventKey
        title    = $Title
        body     = $Body
        cwdName  = $CwdName
        webhooks = $Config.webhooks
    }
    $tempFile = Join-Path $env:TEMP ("claude-toast-webhook-{0}.json" -f [Guid]::NewGuid().ToString('N'))
    try {
        $payload | ConvertTo-Json -Depth 8 -Compress | Out-File -FilePath $tempFile -Encoding UTF8
        $args = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$worker`" -PayloadFile `"$tempFile`" -PluginRoot `"$PluginRoot`""
        Start-Process -FilePath 'powershell.exe' -ArgumentList $args -WindowStyle Hidden | Out-Null
    } catch {
        Write-NotifyLog "Async webhook launch failed, falling back to sync: $_" -Level 'WARN'
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force -ErrorAction SilentlyContinue }
        Send-WebhooksSync -EventKey $EventKey -Title $Title -Body $Body -CwdName $CwdName -Config $Config
    }
}
