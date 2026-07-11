function Get-PluginVersion {
    param([string]$PluginRoot)
    $pluginJson = Join-Path $PluginRoot '.claude-plugin\plugin.json'
    if (Test-Path $pluginJson) {
        try { return (Get-Content -Raw $pluginJson | ConvertFrom-Json).version } catch { }
    }
    return 'unknown'
}
