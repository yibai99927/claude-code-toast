$script:WinRTAvailable = $null
$script:ToastAumid = 'ClaudeCode.Toast'

function Test-WinRTAvailable {
    if ($null -ne $script:WinRTAvailable) { return $script:WinRTAvailable }
    try {
        $null = [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        $null = [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $script:WinRTAvailable = $true
        return $true
    } catch {
        $script:WinRTAvailable = $false
        return $false
    }
}

function Escape-Xml {
    param([string]$Text)
    if (-not $Text) { return '' }
    $Text = $Text.Replace('&', '&amp;')
    $Text = $Text.Replace('"', '&quot;')
    $Text = $Text.Replace("'", '&apos;')
    $Text = $Text.Replace('<', '&lt;')
    $Text = $Text.Replace('>', '&gt;')
    return $Text
}

function Get-ToastIconUri {
    param([string]$PluginRoot)
    $iconPath = Join-Path $PluginRoot 'ClaudeCode-logo.ico'
    if (-not (Test-Path $iconPath)) { return $null }
    try {
        $full = (Resolve-Path $iconPath).Path
        return ([Uri]$full).AbsoluteUri
    } catch { return $null }
}

function Get-ToastActionsXml {
    param(
        [string]$ClickAction,
        [string]$ProjectPath,
        [string]$ActionLabel
    )
    if ($ClickAction -ne 'openFolder') { return '' }
    if ([string]::IsNullOrWhiteSpace($ProjectPath)) { return '' }
    if (-not (Test-Path $ProjectPath)) { return '' }
    try {
        $folderUri = ([Uri]$ProjectPath).AbsoluteUri
        $escLabel = Escape-Xml $ActionLabel
        $escArgs  = Escape-Xml $folderUri
        return "<actions><action content=`"$escLabel`" activationType=`"protocol`" arguments=`"$escArgs`"/></actions>"
    } catch { return '' }
}

function Send-WinRTToast {
    param(
        $Title,
        $Body,
        [string]$Audio = 'Default',
        [string]$PluginRoot = $PSScriptRoot,
        [string]$ClickAction = 'openFolder',
        [string]$ProjectPath = '',
        [string]$ActionLabel = 'Open Folder'
    )
    if (-not (Test-WinRTAvailable)) { return $false }
    try {
        $escTitle = Escape-Xml $Title
        $escBody  = Escape-Xml $Body
        $iconUri  = Get-ToastIconUri $PluginRoot
        $imageXml = ''
        if ($iconUri) {
            $imageXml = "<image placement=`"appLogoOverride`" hint-crop=`"circle`" src=`"$iconUri`"/>"
        }
        $actionsXml = Get-ToastActionsXml $ClickAction $ProjectPath $ActionLabel
        $xmlStr = "<toast duration=`"short`"><visual><binding template=`"ToastGeneric`">$imageXml<text>$escTitle</text><text>$escBody</text></binding></visual><audio src=`"ms-winsoundevent:Notification.$Audio`"/>$actionsXml</toast>"
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml($xmlStr)
        $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
        $toast.ExpirationTime = [DateTimeOffset]::Now.AddSeconds(30)

        $notifier = $null
        $aumids = @(
            $script:ToastAumid,
            'Microsoft.Windows.Explorer',
            '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        )
        foreach ($appId in $aumids) {
            try {
                $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId)
                break
            } catch { }
        }
        if ($null -eq $notifier) { return $false }
        $notifier.Show($toast)
        return $true
    } catch { return $false }
}

function Get-NotifyIconFromPlugin {
    param([string]$PluginRoot)
    $iconPath = Join-Path $PluginRoot 'ClaudeCode-logo.ico'
    if (-not (Test-Path $iconPath)) { return $null }
    try {
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
        return [System.Drawing.Icon]::ExtractAssociatedIcon($iconPath)
    } catch {
        try {
            return New-Object System.Drawing.Icon($iconPath)
        } catch { return $null }
    }
}

function Send-BalloonTip {
    param(
        $Title,
        $Body,
        [string]$Sound = 'Asterisk',
        [string]$PluginRoot = $PSScriptRoot
    )
    try {
        Add-Type -AssemblyName System.Windows.Forms -ErrorAction Stop
        Add-Type -AssemblyName System.Drawing -ErrorAction Stop
    } catch { return $false }
    try {
        $customIcon = Get-NotifyIconFromPlugin $PluginRoot
        $notifyIcon = New-Object System.Windows.Forms.NotifyIcon
        $notifyIcon.Icon = if ($customIcon) { $customIcon } else { [System.Drawing.SystemIcons]::Information }
        $notifyIcon.BalloonTipTitle = $Title
        $notifyIcon.BalloonTipText  = $Body
        $notifyIcon.Visible = $true
        $notifyIcon.ShowBalloonTip(8000)
        Start-Sleep -Milliseconds 500
        $notifyIcon.Dispose()
        if ($customIcon) { $customIcon.Dispose() }
        return $true
    } catch { return $false }
}

function Play-NotifySound {
    param([string]$Sound)
    try {
        switch ($Sound) {
            'Asterisk'    { [System.Media.SystemSounds]::Asterisk.Play() }
            'Exclamation' { [System.Media.SystemSounds]::Exclamation.Play() }
            'Hand'        { [System.Media.SystemSounds]::Hand.Play() }
            'Question'    { [System.Media.SystemSounds]::Question.Play() }
        }
    } catch { }
}

function Send-Notification {
    param(
        $Msg,
        $Config,
        [string]$PluginRoot
    )
    $toastOk = $false
    $balloonOk = $false
    $doToast = if ($Config.enableToast -is [bool]) { $Config.enableToast } else { $true }
    $doSound = if ($Config.enableSound -is [bool]) { $Config.enableSound } else { $true }
    $clickAction = Get-ConfigValue $Config 'toastClickAction' 'openFolder'
    $actionLabel = Get-ToastActionLabel $Config
    $projectPath = if ($Msg.ProjectPath) { $Msg.ProjectPath } else { '' }

    if ($doToast) {
        $toastOk = Send-WinRTToast -Title $Msg.Title -Body $Msg.Body -Audio $Msg.ToastAudio `
            -PluginRoot $PluginRoot -ClickAction $clickAction -ProjectPath $projectPath -ActionLabel $actionLabel
        if (-not $toastOk) {
            Write-NotifyLog 'WinRT toast failed, trying balloon fallback'
            $balloonOk = Send-BalloonTip -Title $Msg.Title -Body $Msg.Body -Sound $Msg.Sound -PluginRoot $PluginRoot
            if ($doSound) { Play-NotifySound $Msg.Sound }
            if (-not $balloonOk) {
                Write-NotifyLog 'Both toast and balloon failed, console only'
                try {
                    Write-Host '--- Claude Code Notification ---'
                    Write-Host "$($Msg.Title)"
                    Write-Host "$($Msg.Body)"
                } catch { }
            }
        }
    } elseif ($doSound) {
        Play-NotifySound $Msg.Sound
    }

    if ($toastOk) { return 'toast' }
    if ($balloonOk) { return 'balloon' }
    return 'console'
}
