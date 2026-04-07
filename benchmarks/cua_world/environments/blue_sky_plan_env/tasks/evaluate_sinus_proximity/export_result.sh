# Note: This content corresponds to C:\workspace\tasks\evaluate_sinus_proximity\export_result.ps1

# --- CONTENT OF C:\workspace\tasks\evaluate_sinus_proximity\export_result.ps1 ---
<#
.SYNOPSIS
Exports results for the sinus evaluation task.
#>

$ErrorActionPreference = "Continue"
Write-Output "=== Exporting Task Results ==="

# 1. Define paths
$reportPath = "C:\Users\Docker\Documents\sinus_evaluation_report.txt"
$taskStartTimePath = "C:\tmp\task_start_time.txt"
$resultJsonPath = "C:\tmp\task_result.json"

# 2. Get Task Start Time
if (Test-Path $taskStartTimePath) {
    $taskStart = Get-Content $taskStartTimePath
} else {
    $taskStart = 0
}

# 3. Check Report File
$reportExists = $false
$reportCreatedDuringTask = $false
$reportContent = ""

if (Test-Path $reportPath) {
    $reportExists = $true
    $fileInfo = Get-Item $reportPath
    $creationTime = Get-Date $fileInfo.CreationTime -UFormat %s
    $lastWriteTime = Get-Date $fileInfo.LastWriteTime -UFormat %s
    
    # Check if created/modified after start
    if ($lastWriteTime -gt $taskStart) {
        $reportCreatedDuringTask = $true
    }
    
    $reportContent = Get-Content $reportPath -Raw
}

# 4. Check Ground Truth
$gtPath = "C:\workspace\ground_truth\sinus_heights.json"
$groundTruth = @{}
if (Test-Path $gtPath) {
    $jsonContent = Get-Content $gtPath -Raw
    $groundTruth = $jsonContent | ConvertFrom-Json
}

# 5. Export result to JSON
$result = @{
    "task_start" = $taskStart
    "report_exists" = $reportExists
    "report_created_during_task" = $reportCreatedDuringTask
    "report_content" = $reportContent
    "ground_truth" = $groundTruth
    "timestamp" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

$result | ConvertTo-Json -Depth 5 | Out-File -Encoding ASCII $resultJsonPath

Write-Output "Result saved to $resultJsonPath"
Get-Content $resultJsonPath
Write-Output "=== Export Complete ==="