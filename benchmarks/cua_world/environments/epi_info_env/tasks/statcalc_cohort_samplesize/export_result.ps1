# Note: This is a PowerShell script saved with .ps1 extension in the environment
# Content of export_result.ps1

Write-Host "=== Exporting StatCalc Task Results ==="

$resultJsonPath = "C:\Users\Docker\Documents\task_result.json"
$outputFile = "C:\Users\Docker\Documents\silicosis_sample_size.txt"
$startTimeFile = "C:\Users\Docker\Documents\task_start_time.txt"

# 1. Get Task Start Time
$taskStart = 0
if (Test-Path $startTimeFile) {
    $taskStart = Get-Content $startTimeFile | ForEach-Object { [int64]$_ }
}

# 2. Check Output File
$outputExists = $false
$fileCreatedDuringTask = $false
$contentValue = $null

if (Test-Path $outputFile) {
    $outputExists = $true
    $fileInfo = Get-Item $outputFile
    $creationTime = [DateTimeOffset]::new($fileInfo.CreationTime).ToUnixTimeSeconds()
    $writeTime = [DateTimeOffset]::new($fileInfo.LastWriteTime).ToUnixTimeSeconds()
    
    if ($writeTime -gt $taskStart) {
        $fileCreatedDuringTask = $true
    }

    # Read content
    try {
        $rawContent = Get-Content $outputFile -Raw
        $contentValue = $rawContent.Trim()
    } catch {
        $contentValue = "ERROR_READING_FILE"
    }
}

# 3. Check if Epi Info is running
$appRunning = [bool](Get-Process "EpiInfo" -ErrorAction SilentlyContinue)

# 4. Create Result JSON
$resultObject = @{
    task_start = $taskStart
    output_exists = $outputExists
    file_created_during_task = $fileCreatedDuringTask
    content_value = $contentValue
    app_was_running = $appRunning
}

$resultObject | ConvertTo-Json -Depth 2 | Out-File -FilePath $resultJsonPath -Encoding ascii -Force

Write-Host "Result saved to $resultJsonPath"
Get-Content $resultJsonPath
Write-Host "=== Export Complete ==="