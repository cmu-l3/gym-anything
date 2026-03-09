#!/bin/powershell
# Export script for Organize Inventory Categories task
# Note: This is a PowerShell script (export_result.ps1)

Write-Host "=== Exporting Task Results ==="

# Define paths
$taskStartTimeFile = "C:\Users\Docker\Documents\task_start_time.txt"
$outputFile = "C:\Users\Docker\Documents\category_assignments.txt"
$resultJsonFile = "C:\Users\Docker\Documents\task_result.json"
$finalScreenshotPath = "C:\Users\Docker\Documents\task_final.png"

# Read start time
$startTime = 0
if (Test-Path $taskStartTimeFile) {
    $startTime = Get-Content $taskStartTimeFile
}

# Check output file
$outputExists = $false
$fileCreatedDuringTask = $false
$fileContent = ""

if (Test-Path $outputFile) {
    $outputExists = $true
    $item = Get-Item $outputFile
    $creationTime = [int][double]::Parse((Get-Date -Date $item.LastWriteTime -UFormat %s))
    
    if ($creationTime -ge $startTime) {
        $fileCreatedDuringTask = $true
    }
    
    # Read content for the verifier
    $fileContent = Get-Content $outputFile -Raw
}

# Check if Copper is running
$appRunning = $false
if (Get-Process -Name "copper" -ErrorAction SilentlyContinue) {
    $appRunning = $true
}

# Take screenshot (using NirCmd or similar if available, or rely on framework)
# Assuming framework handles VLM screenshots, we just export status here.

# Create Result Object
$result = @{
    task_start = $startTime
    output_exists = $outputExists
    file_created_during_task = $fileCreatedDuringTask
    app_was_running = $appRunning
    file_content = $fileContent
}

# Convert to JSON and save
$result | ConvertTo-Json -Depth 5 | Out-File -FilePath $resultJsonFile -Encoding UTF8

# Standard Output for debugging
Write-Host "Result exported to $resultJsonFile"
Get-Content $resultJsonFile