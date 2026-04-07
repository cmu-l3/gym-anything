# Note: This is actually a PowerShell script (export_result.ps1) wrapped in sh
# Content for C:\workspace\tasks\classic_analysis_pgm_export\export_result.ps1

$ErrorActionPreference = "Continue"
Write-Output "=== Exporting Results ==="

# 1. Define paths
$taskStartTimeFile = "C:\temp\task_start_time.txt"
$exportPath = "C:\Users\Docker\Documents\OswegoIllExport.csv"
$resultJsonPath = "C:\temp\task_result.json"

# 2. Get Task Start Time
$startTime = 0
if (Test-Path $taskStartTimeFile) {
    $startTime = [int](Get-Content $taskStartTimeFile)
}

# 3. Analyze Output File
$outputExists = $false
$fileCreatedDuringTask = $false
$fileSize = 0
$rows = 0

if (Test-Path $exportPath) {
    $outputExists = $true
    $fileItem = Get-Item $exportPath
    $fileSize = $fileItem.Length
    
    # Check creation/modification time
    $modTime = [int][double]::Parse((Get-Date $fileItem.LastWriteTime -UFormat %s))
    if ($modTime -gt $startTime) {
        $fileCreatedDuringTask = $true
    }
    
    # Count rows (minus header)
    try {
        $rows = (Get-Content $exportPath | Measure-Object).Count - 1
    } catch {
        $rows = 0
    }
}

# 4. Check if Epi Info is running
$appRunning = [bool](Get-Process "Epi Info 7" -ErrorAction SilentlyContinue)

# 5. Capture Final Screenshot
if (Get-Command python -ErrorAction SilentlyContinue) {
    python -c "import pyautogui; pyautogui.screenshot('C:\\temp\\task_final.png')" 2>$null
}

# 6. Create JSON Result
$jsonContent = @{
    task_start = $startTime
    output_exists = $outputExists
    file_created_during_task = $fileCreatedDuringTask
    output_size_bytes = $fileSize
    row_count_estimate = $rows
    app_was_running = $appRunning
    output_path = $exportPath
} | ConvertTo-Json

$jsonContent | Out-File $resultJsonPath -Encoding ASCII

Write-Output "Result saved to $resultJsonPath"
Write-Output $jsonContent
Write-Output "=== Export Complete ==="