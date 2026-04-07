# This is a PowerShell script (export_result.ps1)

Write-Host "=== Exporting task results ==="

$taskEndTime = [int][double]::Parse((Get-Date -UFormat %s))
$taskStartTime = 0
if (Test-Path "C:\workspace\task_start_time.txt") {
    $taskStartTime = Get-Content "C:\workspace\task_start_time.txt"
}

# Define Expected Paths
$pdfPath = "C:\workspace\intruder_evidence.pdf"
$screenPath = "C:\workspace\intruder_report_screen.png"

# Check PDF
$pdfExists = $false
$pdfSize = 0
$pdfCreatedDuringTask = $false

if (Test-Path $pdfPath) {
    $pdfExists = $true
    $fileItem = Get-Item $pdfPath
    $pdfSize = $fileItem.Length
    
    # Check creation time vs task start
    $creationTime = [int][double]::Parse((Get-Date -Date $fileItem.CreationTime -UFormat %s))
    $lastWriteTime = [int][double]::Parse((Get-Date -Date $fileItem.LastWriteTime -UFormat %s))
    
    if ($creationTime -gt $taskStartTime -or $lastWriteTime -gt $taskStartTime) {
        $pdfCreatedDuringTask = $true
    }
}

# Check Screenshot
$screenExists = $false
if (Test-Path $screenPath) {
    $screenExists = $true
}

# Create Result Object
$result = @{
    task_start = $taskStartTime
    task_end = $taskEndTime
    pdf_exists = $pdfExists
    pdf_created_during_task = $pdfCreatedDuringTask
    pdf_size_bytes = $pdfSize
    screenshot_exists = $screenExists
    pdf_path = $pdfPath
    screenshot_path = $screenPath
}

# Convert to JSON and save
$jsonContent = $result | ConvertTo-Json
Set-Content -Path "C:\workspace\task_result.json" -Value $jsonContent

Write-Host "Result saved to C:\workspace\task_result.json"
Write-Host $jsonContent
Write-Host "=== Export complete ==="