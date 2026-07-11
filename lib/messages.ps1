function Get-WorkingDirName {
    param($PayloadCwd)
    if (-not $PayloadCwd) { return '' }
    try { return (Split-Path $PayloadCwd -Leaf) } catch { return $PayloadCwd }
}

function Get-SummaryPreview {
    param($Text, $MaxChars)
    if ([string]::IsNullOrWhiteSpace($Text)) { return '' }
    $Text = $Text.Trim()
    if ($Text.Length -le $MaxChars) { return $Text }
    return $Text.Substring(0, $MaxChars) + [char]0x2026
}

$script:NotifyTemplates = @{
    'task_done' = @{
        TitleEmoji    = [char]0x2705
        TitleSuffix   = [char]0x4EFB + [char]0x52A1 + [char]0x5B8C + [char]0x6210
        TitleSuffixEn = 'Task Done'
        Sound         = 'Asterisk'
        ToastAudio    = 'Default'
    }
    'failed' = @{
        TitleEmoji    = [char]0x274C
        TitleSuffix   = [char]0x6267 + [char]0x884C + [char]0x5F02 + [char]0x5E38
        TitleSuffixEn = 'Error'
        Sound         = 'Hand'
        ToastAudio    = 'Looping.Alarm2'
    }
    'needs_input' = @{
        TitleEmoji    = [char]0x23F3
        TitleSuffix   = [char]0x7B49 + [char]0x5F85 + [char]0x8F93 + [char]0x5165
        TitleSuffixEn = 'Waiting'
        Sound         = 'Asterisk'
        ToastAudio    = 'IM'
    }
    'permission_required' = @{
        TitleEmoji    = [char]::ConvertFromUtf32(0x1F510)
        TitleSuffix   = [char]0x8BF7 + [char]0x6C42 + [char]0x6743 + [char]0x9650
        TitleSuffixEn = 'Permission'
        Sound         = 'Exclamation'
        ToastAudio    = 'Reminder'
    }
    'question' = @{
        TitleEmoji    = [char]::ConvertFromUtf32(0x1F4AC)
        TitleSuffix   = [char]0x63D0 + [char]0x95EE
        TitleSuffixEn = 'Question'
        Sound         = 'Question'
        ToastAudio    = 'Looping.Alarm4'
    }
    'plan_ready' = @{
        TitleEmoji    = [char]::ConvertFromUtf32(0x1F4CB)
        TitleSuffix   = [char]0x8BA1 + [char]0x5212 + [char]0x5C31 + [char]0x7EEA
        TitleSuffixEn = 'Plan Ready'
        Sound         = 'Exclamation'
        ToastAudio    = 'Mail'
    }
    'subtask_done' = @{
        TitleEmoji    = [char]::ConvertFromUtf32(0x1F916)
        TitleSuffix   = [char]0x5B50 + [char]0x4EFB + [char]0x52A1 + [char]0x5B8C + [char]0x6210
        TitleSuffixEn = 'Subtask Done'
        Sound         = 'Asterisk'
        ToastAudio    = 'Default'
    }
    'session' = @{
        Sound      = 'Asterisk'
        ToastAudio = 'Default'
    }
}

$script:ChsBody = @{
    responseFinished  = [char]0x54CD + [char]0x5E94 + [char]0x7ED3 + [char]0x675F
    stoppedUnexpected = 'Claude ' + [char]0x5F02 + [char]0x5E38 + [char]0x505C + [char]0x6B62 + [char]0x6216 + [char]0x9047 + [char]0x5230 + [char]0x9519 + [char]0x8BEF
    waitingReply      = [char]0x7B49 + [char]0x5F85 + [char]0x4F60 + [char]0x7684 + [char]0x56DE + [char]0x590D
    permissionNeeded  = [char]0x9700 + [char]0x8981 + [char]0x6743 + [char]0x9650 + [char]0x6267 + [char]0x884C + ' '
    hasQuestion       = [char]0x6709 + [char]0x95EE + [char]0x9898 + [char]0x9700 + [char]0x8981 + [char]0x4F60 + [char]0x56DE + [char]0x7B54
    planReadyBody     = [char]0x8BA1 + [char]0x5212 + [char]0x5DF2 + [char]0x751F + [char]0x6210 + [char]0xFF0C + [char]0x7B49 + [char]0x5F85 + [char]0x786E + [char]0x8BA4
    subtaskFinished   = [char]0x5B50 + [char]0x4EFB + [char]0x52A1 + [char]0x7ED3 + [char]0x675F
    sessionStarted    = [char]0x4F1A + [char]0x8BDD + [char]0x5F00 + [char]0x59CB
    sessionEnded      = [char]0x4F1A + [char]0x8BDD + [char]0x7ED3 + [char]0x675F
    toolDefault       = [char]0x5DE5 + [char]0x5177
    completed         = [char]0x5B8C + [char]0x6210
    openFolder        = [char]0x6253 + [char]0x5F00 + [char]0x6587 + [char]0x4EF6 + [char]0x5939
}

$script:EnBody = @{
    responseFinished  = 'Response finished'
    stoppedUnexpected = 'Claude stopped unexpectedly or encountered an error'
    waitingReply      = 'Waiting for your reply'
    permissionNeeded  = 'Needs permission to run '
    hasQuestion       = 'Has a question for you'
    planReadyBody     = 'Plan is ready for review'
    subtaskFinished   = 'Subtask finished'
    sessionStarted    = 'Session started'
    sessionEnded      = 'Session ended'
    toolDefault       = 'tool'
    completed         = 'Done'
    openFolder        = 'Open Folder'
}

function Build-NotificationMessage {
    param($Type, $Payload, $Config)
    $cwdName = if ($Config.showCwd) { Get-WorkingDirName $Payload.cwd } else { '' }
    $cwdLabel = if ($cwdName) { "$cwdName - " } else { '' }
    $t = $script:NotifyTemplates[$Type]
    $useEn = ($Config.language -eq 'en')
    $b  = if ($useEn) { $script:EnBody } else { $script:ChsBody }
    $sfx = if ($useEn -and ($t.ContainsKey('TitleSuffixEn'))) { $t.TitleSuffixEn } else { $t.TitleSuffix }

    switch ($Type) {
        'task_done' {
            $title = $t.TitleEmoji + ' ' + $sfx
            if ($Config.showSummary -and $Payload.last_assistant_message) {
                $body = Get-SummaryPreview $Payload.last_assistant_message $Config.summaryMaxChars
            } elseif ($cwdName) {
                $body = $cwdLabel + $b.responseFinished
            } else {
                $body = $b.responseFinished
            }
            return @{ Title = $title; Body = $body; Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd }
        }
        'failed' {
            return @{
                Title = $t.TitleEmoji + ' ' + $sfx
                Body  = $cwdLabel + $b.stoppedUnexpected
                Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd
            }
        }
        'needs_input' {
            $ntype = if ($Payload.notification_type) { " ($($Payload.notification_type))" } else { '' }
            return @{
                Title = $t.TitleEmoji + ' ' + $sfx
                Body  = $cwdLabel + $b.waitingReply + $ntype
                Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd
            }
        }
        'permission_required' {
            $tool = if ($Payload.tool_name) { $Payload.tool_name } else { $b.toolDefault }
            $action = ''
            if ($Payload.tool_input) {
                $inp = $Payload.tool_input
                if ($inp -is [string]) {
                    $action = if ($inp.Length -gt 80) { $inp.Substring(0, 80) + [char]0x2026 } else { $inp }
                } else { $action = "$inp" }
            }
            $body = $cwdLabel + $b.permissionNeeded + $tool
            if ($action) { $body += "`n$action" }
            return @{ Title = ($t.TitleEmoji + ' ' + $sfx); Body = $body; Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd }
        }
        'question' {
            return @{
                Title = $t.TitleEmoji + ' Claude ' + $sfx
                Body  = $cwdLabel + $b.hasQuestion
                Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd
            }
        }
        'plan_ready' {
            return @{
                Title = $t.TitleEmoji + ' ' + $sfx
                Body  = $cwdLabel + $b.planReadyBody
                Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd
            }
        }
        'subtask_done' {
            $sub = if ($Payload.teammate_name) { $Payload.teammate_name }
                   elseif ($Payload.task_subject) { $Payload.task_subject }
                   else { '' }
            $body = if ($sub) { $b.completed + ': ' + $sub } else { $cwdLabel + $b.subtaskFinished }
            return @{ Title = ($t.TitleEmoji + ' ' + $sfx); Body = $body; Sound = $t.Sound; ToastAudio = $t.ToastAudio; ProjectPath = $Payload.cwd }
        }
        'session' {
            $emoji = if ($Payload.hook_event_name -eq 'SessionStart') { [char]0x25B6 } else { [char]0x23F9 }
            $verb  = if ($Payload.hook_event_name -eq 'SessionStart') { $b.sessionStarted } else { $b.sessionEnded }
            return @{
                Title = $emoji + ' ' + $verb
                Body  = if ($cwdName) { $cwdName } else { '' }
                Sound = 'Asterisk'; ToastAudio = 'Default'; ProjectPath = $Payload.cwd
            }
        }
        default { return $null }
    }
}

function Get-ToastActionLabel {
    param($Config)
    $useEn = ($Config.language -eq 'en')
    $b = if ($useEn) { $script:EnBody } else { $script:ChsBody }
    return $b.openFolder
}
