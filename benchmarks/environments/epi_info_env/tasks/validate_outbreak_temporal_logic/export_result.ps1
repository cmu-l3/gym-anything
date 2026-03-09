# Note: Providing content for C:\workspace\tasks\validate_outbreak_temporal_logic\export_result.ps1

Write-Host "=== Exporting Task Results ==="

$DocPath = "C:\Users\Docker\Documents\EpiInfoData"
$ResultFile = "$DocPath\Temporal_Errors.html"
$JsonPath = "C:\tmp\task_result.json"
$StartTimeFile = "C:\tmp\task_start_time.txt"

# 1. Check if output file exists
$OutputExists = $false
$FileCreatedDuringTask = $false
$OutputSize = 0
$Content = ""

if (Test-Path $ResultFile) {
    $OutputExists = $true
    $Item = Get-Item $ResultFile
    $OutputSize = $Item.Length
    
    # Read content for verification (first 5000 chars to avoid huge files)
    $Content = Get-Content $ResultFile -Raw
    if ($Content.Length -gt 5000) { $Content = $Content.Substring(0, 5000) }
    
    # Check timestamp
    if (Test-Path $StartTimeFile) {
        $TaskStart = [int64](Get-Content $StartTimeFile)
        # Convert file write time to epoch
        $FileTime = [Math]::Floor((New-TimeSpan -Start (Get-Date "01/01/1970") -End $Item.LastWriteTime).TotalSeconds)
        
        if ($FileTime -gt $TaskStart) {
            $FileCreatedDuringTask = $true
        }
    }
}

# 2. Check if App is Running
$AppRunning = $false
if (Get-Process "Analysis" -ErrorAction SilentlyContinue) {
    $AppRunning = $true
}

# 3. Create JSON Result
# Escape content for JSON
$EncodedContent = $Content -replace '\\', '\\\\' -replace '"', '\"' -replace "`r", '' -replace "`n", '\n'

$Json = @"
{
    "output_exists": $OutputExists,
    "file_created_during_task": $FileCreatedDuringTask,
    "output_size_bytes": $OutputSize,
    "app_was_running": $AppRunning,
    "file_content_snippet": "$EncodedContent",
    "timestamp": "$(Get-Date -Format s)"
}
"@

$Json | Out-File -FilePath $JsonPath -Encoding UTF8

Write-Host "Result exported to $JsonPath"
Get-Content $JsonPath