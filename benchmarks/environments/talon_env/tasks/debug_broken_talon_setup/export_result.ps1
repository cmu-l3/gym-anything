Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_debug_broken_talon_setup.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting debug_broken_talon_setup result ==="

    $configDir = "C:\Users\Docker\AppData\Roaming\Talon\user\community\user_config"
    $resultFile = "C:\Users\Docker\debug_broken_talon_setup_result.json"

    # Read each file content (empty string if not found)
    function Read-FileOrEmpty($path) {
        if (Test-Path $path) {
            return [System.IO.File]::ReadAllText($path)
        }
        return ""
    }

    $settingsContent  = Read-FileOrEmpty "$configDir\user_settings.talon"
    $windowContent    = Read-FileOrEmpty "$configDir\window_management.talon"
    $listContent      = Read-FileOrEmpty "$configDir\user.browser_shortcuts.talon-list"
    $pythonContent    = Read-FileOrEmpty "$configDir\text_actions.py"

    # Read task start timestamp
    $startTs = ""
    if (Test-Path "C:\Users\Docker\task_start_ts_debug_broken_talon_setup.txt") {
        $startTs = [System.IO.File]::ReadAllText("C:\Users\Docker\task_start_ts_debug_broken_talon_setup.txt").Trim()
    }

    # Get file modification times
    function Get-ModTime($path) {
        if (Test-Path $path) {
            return (Get-Item $path).LastWriteTime.ToString("o")
        }
        return ""
    }

    $settingsMod = Get-ModTime "$configDir\user_settings.talon"
    $windowMod   = Get-ModTime "$configDir\window_management.talon"
    $listMod     = Get-ModTime "$configDir\user.browser_shortcuts.talon-list"
    $pythonMod   = Get-ModTime "$configDir\text_actions.py"

    # Build result object and serialize manually to avoid encoding issues
    # Escape backslashes and double-quotes in content for JSON
    function Escape-Json($s) {
        $s = $s -replace '\\', '\\\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`r`n", '\n'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\n'
        $s = $s -replace "`t", '\t'
        return $s
    }

    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "settings_talon": "$(Escape-Json $settingsContent)",
  "settings_talon_mod": "$(Escape-Json $settingsMod)",
  "window_talon": "$(Escape-Json $windowContent)",
  "window_talon_mod": "$(Escape-Json $windowMod)",
  "list_file": "$(Escape-Json $listContent)",
  "list_file_mod": "$(Escape-Json $listMod)",
  "python_file": "$(Escape-Json $pythonContent)",
  "python_file_mod": "$(Escape-Json $pythonMod)"
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
