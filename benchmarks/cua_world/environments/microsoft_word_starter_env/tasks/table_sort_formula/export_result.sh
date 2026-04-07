# Note: In the Windows environment, this is actually export_result.ps1
# The extension .sh is used here for syntax highlighting compatibility.

Write-Host "=== Exporting Task Results ==="

$resultPath = "C:\Users\Docker\task_result.json"
$docPath = "C:\Users\Docker\Documents\quarterly_expenses.docx"
$startTimePath = "C:\Users\Docker\task_start_time.txt"

# 1. Get Task Timings
$taskEnd = [DateTimeOffset]::Now.ToUnixTimeSeconds()
if (Test-Path $startTimePath) {
    $taskStart = Get-Content $startTimePath
} else {
    $taskStart = 0
}

# 2. Check Output File
$outputExists = $false
$fileCreatedDuringTask = $false
$outputSize = 0
$lastModified = 0

if (Test-Path $docPath) {
    $outputExists = $true
    $item = Get-Item $docPath
    $outputSize = $item.Length
    
    # Convert DateTime to Unix Timestamp
    $lastModifiedObj = $item.LastWriteTime
    $lastModified = [DateTimeOffset]::new($lastModifiedObj).ToUnixTimeSeconds()
    
    # Check if modified after start (allow small buffer)
    if ($lastModified -ge $taskStart) {
        $fileCreatedDuringTask = $true
    }
}

# 3. Check if Word is running
$proc = Get-Process "WINWORD" -ErrorAction SilentlyContinue
$appRunning = ($proc -ne $null)

# 4. Create JSON Result
$json = @{
    task_start = [int64]$taskStart
    task_end = [int64]$taskEnd
    output_exists = $outputExists
    file_created_during_task = $fileCreatedDuringTask
    output_size_bytes = $outputSize
    app_was_running = $appRunning
    output_path = $docPath
} | ConvertTo-Json

$json | Out-File -FilePath $resultPath -Encoding ascii

Write-Host "Result saved to $resultPath"
Write-Host "=== Export Complete ==="