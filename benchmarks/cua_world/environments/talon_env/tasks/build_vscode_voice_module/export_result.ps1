Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_build_vscode_voice_module.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting build_vscode_voice_module result ==="

    $targetDir  = "C:\Users\Docker\AppData\Roaming\Talon\user\community\apps\vscode"
    $talonFile  = "$targetDir\vscode.talon"
    $pyFile     = "$targetDir\vscode.py"
    $resultFile = "C:\Users\Docker\build_vscode_voice_module_result.json"

    function Read-FileOrEmpty($path) {
        if (Test-Path $path) {
            return [System.IO.File]::ReadAllText($path)
        }
        return ""
    }

    function Get-ModTime($path) {
        if (Test-Path $path) {
            return (Get-Item $path).LastWriteTime.ToString("o")
        }
        return ""
    }

    function Escape-Json($s) {
        $s = $s -replace '\\', '\\\\'
        $s = $s -replace '"', '\"'
        $s = $s -replace "`r`n", '\n'
        $s = $s -replace "`n", '\n'
        $s = $s -replace "`r", '\n'
        $s = $s -replace "`t", '\t'
        return $s
    }

    $talonContent = Read-FileOrEmpty $talonFile
    $pyContent    = Read-FileOrEmpty $pyFile
    $talonMod     = Get-ModTime $talonFile
    $pyMod        = Get-ModTime $pyFile

    $startTs = ""
    if (Test-Path "C:\Users\Docker\task_start_ts_build_vscode_voice_module.txt") {
        $startTs = [System.IO.File]::ReadAllText("C:\Users\Docker\task_start_ts_build_vscode_voice_module.txt").Trim()
    }

    # Count .talon files in directory (should be at least vscode.talon)
    $talonFileCount = (Get-ChildItem -Path $targetDir -Filter "*.talon" -ErrorAction SilentlyContinue).Count
    $pyFileCount    = (Get-ChildItem -Path $targetDir -Filter "*.py"    -ErrorAction SilentlyContinue).Count

    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "talon_file_exists": $(if (Test-Path $talonFile) { "true" } else { "false" }),
  "py_file_exists": $(if (Test-Path $pyFile) { "true" } else { "false" }),
  "talon_content": "$(Escape-Json $talonContent)",
  "py_content": "$(Escape-Json $pyContent)",
  "talon_mod": "$(Escape-Json $talonMod)",
  "py_mod": "$(Escape-Json $pyMod)",
  "talon_file_count": $talonFileCount,
  "py_file_count": $pyFileCount
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
