# Setup script for Cystic Fibrosis Pedigree Chart task (Windows)

$ErrorActionPreference = "Continue"

Write-Host "=== Setting up Cystic Fibrosis Pedigree Chart Task ==="

# Source shared utilities
. C:\workspace\scripts\task_utils.ps1

# Ensure Flipcharts directory exists
New-Item -ItemType Directory -Force -Path "C:\Users\Docker\Documents\Flipcharts" | Out-Null

# Remove any pre-existing target file to ensure clean start
$targetFile = "C:\Users\Docker\Documents\Flipcharts\cystic_fibrosis_pedigree.flipchart"
$targetFileAlt = "C:\Users\Docker\Documents\Flipcharts\cystic_fibrosis_pedigree.flp"

if (Test-Path $targetFile) {
    Write-Host "Removing pre-existing: $targetFile"
    Remove-Item $targetFile -Force -ErrorAction SilentlyContinue
}
if (Test-Path $targetFileAlt) {
    Write-Host "Removing pre-existing: $targetFileAlt"
    Remove-Item $targetFileAlt -Force -ErrorAction SilentlyContinue
}

# Record baseline flipchart count
$initialCount = Get-FlipchartCount
[System.IO.File]::WriteAllText("C:\Windows\Temp\initial_flipchart_count", "$initialCount")
Write-Host "Initial flipchart count: $initialCount"

# Record task start time (Unix epoch seconds)
$taskStart = [int][double]::Parse((Get-Date -UFormat %s))
[System.IO.File]::WriteAllText("C:\Windows\Temp\task_start_time", "$taskStart")
Write-Host "Task start time recorded: $taskStart"

# Ensure ActivInspire is running
Ensure-ActivInspireRunning
Start-Sleep -Seconds 3

# Minimize terminal windows for clean desktop
Minimize-TerminalWindows

Write-Host "=== Setup Complete ==="
Write-Host "Target: $targetFile"
