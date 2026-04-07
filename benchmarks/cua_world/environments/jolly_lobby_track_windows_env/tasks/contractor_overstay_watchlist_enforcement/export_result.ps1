# export_result.ps1 — Post-task result export for contractor_overstay_watchlist_enforcement
#
# Collects task outputs into a JSON file for the verifier:
#   - Whether the compliance report CSV exists, its size and timestamp
#   - The CSV file content (for programmatic content checks)
#   - Task start time (for anti-gaming timestamp verification)
#   - Whether Lobby Track is still running

$ErrorActionPreference = "Continue"

Write-Host "=== Exporting results for contractor_overstay_watchlist_enforcement ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Build result object
$result = @{
    task = "contractor_overstay_watchlist_enforcement"
    timestamp = [int](Get-Date -UFormat %s)
}

# Check for the compliance report output file
$outputPath = "C:\Users\Docker\Desktop\watchlist_enforcement_dec2025.csv"
if (Test-Path $outputPath) {
    $fileInfo = Get-Item $outputPath
    $result["output_exists"] = $true
    $result["output_file"] = $outputPath
    $result["output_size"] = $fileInfo.Length
    $result["output_last_write"] = [int]($fileInfo.LastWriteTimeUtc - (Get-Date "1970-01-01")).TotalSeconds

    # Read file content for verification (cap at 10KB to keep JSON manageable)
    try {
        $content = Get-Content $outputPath -Raw -ErrorAction Stop
        if ($content.Length -gt 10240) {
            $result["output_content"] = $content.Substring(0, 10240)
        } else {
            $result["output_content"] = $content
        }
    } catch {
        $result["output_content"] = ""
    }
} else {
    $result["output_exists"] = $false
}

# Record task start time for anti-gaming checks
$startTimePath = "C:\Windows\Temp\contractor_overstay_watchlist_enforcement_start_time"
if (Test-Path $startTimePath) {
    $result["task_start_time"] = [int](Get-Content $startTimePath -ErrorAction SilentlyContinue)
}

# Check if Lobby Track is still running (indicates agent used the GUI)
$result["app_running"] = Test-LobbyTrackRunning

# Write result JSON
$resultJson = $result | ConvertTo-Json -Depth 5
$resultPath = "C:\Windows\Temp\contractor_overstay_watchlist_enforcement_result.json"
[System.IO.File]::WriteAllText($resultPath, $resultJson)
Write-Host "Result exported to: $resultPath"

Write-Host "=== contractor_overstay_watchlist_enforcement export complete ==="
