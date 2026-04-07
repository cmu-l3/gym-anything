Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_build_court_docket_system.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting build_court_docket_system result ==="

    $targetDir  = "C:\Users\Docker\AppData\Roaming\Talon\user\docket_manager"
    $csvPath    = "C:\Users\Docker\Desktop\TalonTasks\court_docket.csv"
    $docDir     = "C:\Users\Docker\Documents"
    $resultFile = "C:\Users\Docker\build_court_docket_system_result.json"

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
    $tsFile = "C:\Users\Docker\task_start_ts_build_court_docket_system.txt"
    if (Test-Path $tsFile) {
        $startTs = [System.IO.File]::ReadAllText($tsFile).Trim()
    }

    # --- Collect docket_manager module files ---
    $dirExists = Test-Path $targetDir

    $pyPath    = "$targetDir\docket_manager.py"
    $listPath  = "$targetDir\case_types.talon-list"
    $talonPath = "$targetDir\docket.talon"

    $pyContent    = Read-FileOrEmpty $pyPath
    $listContent  = Read-FileOrEmpty $listPath
    $talonContent = Read-FileOrEmpty $talonPath

    $pyMod    = Get-ModTime $pyPath
    $listMod  = Get-ModTime $listPath
    $talonMod = Get-ModTime $talonPath

    $pySize    = Get-FileSize $pyPath
    $listSize  = Get-FileSize $listPath
    $talonSize = Get-FileSize $talonPath

    # --- Collect CSV state (may have been modified by docket_continue) ---
    $csvContent = Read-FileOrEmpty $csvPath
    $csvMod     = Get-ModTime $csvPath
    $csvSize    = Get-FileSize $csvPath

    # --- Collect any generated docket sheet output files ---
    $docketSheets = @()
    if (Test-Path $docDir) {
        $sheets = Get-ChildItem -Path $docDir -Filter "docket_*.txt" -ErrorAction SilentlyContinue
        foreach ($sheet in $sheets) {
            $sheetContent = [System.IO.File]::ReadAllText($sheet.FullName)
            $docketSheets += @{
                name    = $sheet.Name
                content = $sheetContent
                mod     = $sheet.LastWriteTime.ToString("o")
                size    = $sheet.Length
            }
        }
    }

    # Build docket_sheets JSON array manually
    $sheetsJson = "[]"
    if ($docketSheets.Count -gt 0) {
        $sheetEntries = @()
        foreach ($s in $docketSheets) {
            $sheetEntries += "{`"name`": `"$(Escape-Json $s.name)`", `"content`": `"$(Escape-Json $s.content)`", `"mod`": `"$(Escape-Json $s.mod)`", `"size`": $($s.size)}"
        }
        $sheetsJson = "[" + ($sheetEntries -join ", ") + "]"
    }

    # --- Build result JSON ---
    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "dir_exists": $(if ($dirExists) { "true" } else { "false" }),
  "py_exists": $(if (Test-Path $pyPath) { "true" } else { "false" }),
  "py_content": "$(Escape-Json $pyContent)",
  "py_mod": "$(Escape-Json $pyMod)",
  "py_size": $pySize,
  "list_exists": $(if (Test-Path $listPath) { "true" } else { "false" }),
  "list_content": "$(Escape-Json $listContent)",
  "list_mod": "$(Escape-Json $listMod)",
  "list_size": $listSize,
  "talon_exists": $(if (Test-Path $talonPath) { "true" } else { "false" }),
  "talon_content": "$(Escape-Json $talonContent)",
  "talon_mod": "$(Escape-Json $talonMod)",
  "talon_size": $talonSize,
  "csv_content": "$(Escape-Json $csvContent)",
  "csv_mod": "$(Escape-Json $csvMod)",
  "csv_size": $csvSize,
  "docket_sheets": $sheetsJson
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"
    Write-Host "  dir_exists=$dirExists py=$(Test-Path $pyPath) list=$(Test-Path $listPath) talon=$(Test-Path $talonPath)"
    Write-Host "  docket_sheets found: $($docketSheets.Count)"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
