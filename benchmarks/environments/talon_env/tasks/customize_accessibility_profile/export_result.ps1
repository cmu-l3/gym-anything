Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$logPath = "C:\Users\Docker\task_export_customize_accessibility_profile.log"
try {
    Start-Transcript -Path $logPath -Force | Out-Null
} catch {
    Write-Host "WARNING: Start-Transcript failed: $($_.Exception.Message)"
}

try {
    Write-Host "=== Exporting customize_accessibility_profile result ==="

    $letterFile = "C:\Users\Docker\AppData\Roaming\Talon\user\community\core\keys\letter.talon-list"
    $medFile    = "C:\Users\Docker\AppData\Roaming\Talon\user\community\core\vocabulary\user.medical_terms.talon-list"
    $resultFile = "C:\Users\Docker\customize_accessibility_profile_result.json"

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

    $letterContent = Read-FileOrEmpty $letterFile
    $medContent    = Read-FileOrEmpty $medFile
    $letterMod     = Get-ModTime $letterFile
    $medMod        = Get-ModTime $medFile

    $startTs = ""
    if (Test-Path "C:\Users\Docker\task_start_ts_customize_accessibility_profile.txt") {
        $startTs = [System.IO.File]::ReadAllText("C:\Users\Docker\task_start_ts_customize_accessibility_profile.txt").Trim()
    }

    $json = @"
{
  "task_start_ts": "$(Escape-Json $startTs)",
  "letter_file_exists": $(if (Test-Path $letterFile) { "true" } else { "false" }),
  "letter_content": "$(Escape-Json $letterContent)",
  "letter_mod": "$(Escape-Json $letterMod)",
  "medical_file_exists": $(if (Test-Path $medFile) { "true" } else { "false" }),
  "medical_content": "$(Escape-Json $medContent)",
  "medical_mod": "$(Escape-Json $medMod)"
}
"@

    [System.IO.File]::WriteAllText($resultFile, $json)
    Write-Host "Result written to: $resultFile"

    Write-Host "=== Export Complete ==="
} finally {
    try { Stop-Transcript | Out-Null } catch { }
}
