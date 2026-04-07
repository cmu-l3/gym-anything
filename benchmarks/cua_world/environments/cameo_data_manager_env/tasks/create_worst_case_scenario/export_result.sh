# Note: This is actually a PowerShell script (export_result.ps1)

Write-Host "=== Exporting Task Results ==="

$TaskStart = Get-Content "C:\tmp\task_start_time.txt"
$OutputPdf = "C:\Users\Docker\Documents\scenario_report.pdf"
$ScreenshotPath = "C:\tmp\task_final.png"

# 1. Take Final Screenshot
python -c "import pyautogui; pyautogui.screenshot('$ScreenshotPath')"

# 2. Check File Existence and Timestamp
$OutputExists = $false
$FileCreatedDuringTask = $false
$FileSize = 0

if (Test-Path $OutputPdf) {
    $OutputExists = $true
    $FileItem = Get-Item $OutputPdf
    $FileSize = $FileItem.Length
    
    # Check creation time (Unix timestamp comparison)
    $FileCreationTime = [int][double]::Parse((Get-Date $FileItem.CreationTime -UFormat %s))
    $FileWriteTime = [int][double]::Parse((Get-Date $FileItem.LastWriteTime -UFormat %s))
    
    if ($FileWriteTime -gt $TaskStart) {
        $FileCreatedDuringTask = $true
    }
}

# 3. Check App State
$AppRunning = $false
if (Get-Process "CAMEO Data Manager" -ErrorAction SilentlyContinue) {
    $AppRunning = $true
}

# 4. Create JSON Result
$Result = @{
    task_start = [int]$TaskStart
    output_exists = $OutputExists
    file_created_during_task = $FileCreatedDuringTask
    output_size_bytes = $FileSize
    app_was_running = $AppRunning
    output_path = $OutputPdf
    screenshot_path = $ScreenshotPath
}

$Json = $Result | ConvertTo-Json

# Save to tmp for the verifier to pull
Set-Content -Path "C:\tmp\task_result.json" -Value $Json

Write-Host "Result exported to C:\tmp\task_result.json"
Write-Host $Json
Write-Host "=== Export Complete ==="