Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_audit_and_deduplicate_commands.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting audit_and_deduplicate_commands result ==="

    $cmdDir     = "C:\Users\Docker\AppData\Roaming\Talon\user\community\user_commands"
    $resultFile = "C:\Users\Docker\audit_and_deduplicate_commands_result.json"

    function Read-FileOrEmpty($path) {
        if (Test-Path $path) { return [System.IO.File]::ReadAllText($path) }
        return ""
    }

    function Get-ModTime($path) {
        if (Test-Path $path) { return (Get-Item $path).LastWriteTime.ToString("o") }
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

    $editorContent      = Read-FileOrEmpty "$cmdDir\editor_commands.talon"
    $generalContent     = Read-FileOrEmpty "$cmdDir\general_commands.talon"
    $productivityContent = Read-FileOrEmpty "$cmdDir\productivity_commands.talon"
    $reportContent      = Read-FileOrEmpty "$cmdDir\audit_report.txt"

    $editorMod       = Get-ModTime "$cmdDir\editor_commands.talon"
    $generalMod      = Get-ModTime "$cmdDir\general_commands.talon"
    $productivityMod = Get-ModTime "$cmdDir\productivity_commands.talon"
    $reportMod       = Get-ModTime "$cmdDir\audit_report.txt"

    $startTs = ""
    if (Test-Path "C:\Users\Docker\task_start_ts_audit_and_deduplicate_commands.txt") {
        $startTs = [System.IO.File]::ReadAllText("C:\Users\Docker\task_start_ts_audit_and_deduplicate_commands.txt").Trim()
    }

    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "editor_content": "$(Escape-Json $editorContent)",
  "editor_mod": "$(Escape-Json $editorMod)",
  "general_content": "$(Escape-Json $generalContent)",
  "general_mod": "$(Escape-Json $generalMod)",
  "productivity_content": "$(Escape-Json $productivityContent)",
  "productivity_mod": "$(Escape-Json $productivityMod)",
  "report_exists": $(if (Test-Path "$cmdDir\audit_report.txt") { "true" } else { "false" }),
  "report_content": "$(Escape-Json $reportContent)",
  "report_mod": "$(Escape-Json $reportMod)"
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
