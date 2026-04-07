Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_rescue_broken_docket_module.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting rescue_broken_docket_module result ==="

    $targetDir  = "C:\Users\Docker\AppData\Roaming\Talon\user\docket_module"
    $reportPath = "C:\Users\Docker\Desktop\TalonTasks\docket_report.txt"
    $resultFile = "C:\Users\Docker\rescue_broken_docket_module_result.json"

    # --- Helper functions ---
    function Read-FileOrEmpty($path) {
        if (Test-Path $path) { return [System.IO.File]::ReadAllText($path) }
        return ""
    }

    function Get-ModTime($path) {
        if (Test-Path $path) { return (Get-Item $path).LastWriteTime.ToString("o") }
        return ""
    }

    function Get-FileSize($path) {
        if (Test-Path $path) { return (Get-Item $path).Length }
        return 0
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

    # --- Read task start timestamp ---
    $startTs = ""
    $tsFile = "C:\Users\Docker\task_start_ts_rescue_broken_docket_module.txt"
    if (Test-Path $tsFile) {
        $startTs = [System.IO.File]::ReadAllText($tsFile).Trim()
    }

    # --- Collect docket_module files ---
    $dirExists = Test-Path $targetDir

    $pyPath    = "$targetDir\docket_engine.py"
    $talonPath = "$targetDir\docket.talon"
    $listPath  = "$targetDir\docket_fields.talon-list"

    $pyContent    = Read-FileOrEmpty $pyPath
    $talonContent = Read-FileOrEmpty $talonPath
    $listContent  = Read-FileOrEmpty $listPath

    $pyMod    = Get-ModTime $pyPath
    $talonMod = Get-ModTime $talonPath
    $listMod  = Get-ModTime $listPath

    $pySize    = Get-FileSize $pyPath
    $talonSize = Get-FileSize $talonPath
    $listSize  = Get-FileSize $listPath

    # --- Collect report file ---
    $reportContent = Read-FileOrEmpty $reportPath
    $reportMod     = Get-ModTime $reportPath
    $reportSize    = Get-FileSize $reportPath
    $reportExists  = Test-Path $reportPath

    # --- Build result JSON ---
    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "dir_exists": $(if ($dirExists) { "true" } else { "false" }),
  "py_exists": $(if (Test-Path $pyPath) { "true" } else { "false" }),
  "py_content": "$(Escape-Json $pyContent)",
  "py_mod": "$(Escape-Json $pyMod)",
  "py_size": $pySize,
  "talon_exists": $(if (Test-Path $talonPath) { "true" } else { "false" }),
  "talon_content": "$(Escape-Json $talonContent)",
  "talon_mod": "$(Escape-Json $talonMod)",
  "talon_size": $talonSize,
  "list_exists": $(if (Test-Path $listPath) { "true" } else { "false" }),
  "list_content": "$(Escape-Json $listContent)",
  "list_mod": "$(Escape-Json $listMod)",
  "list_size": $listSize,
  "report_exists": $(if ($reportExists) { "true" } else { "false" }),
  "report_content": "$(Escape-Json $reportContent)",
  "report_mod": "$(Escape-Json $reportMod)",
  "report_size": $reportSize
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"
    Write-Host "  dir_exists=$dirExists py=$(Test-Path $pyPath) talon=$(Test-Path $talonPath) list=$(Test-Path $listPath)"
    Write-Host "  report_exists=$reportExists report_size=$reportSize"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
