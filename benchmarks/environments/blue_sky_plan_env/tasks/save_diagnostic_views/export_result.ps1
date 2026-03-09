# NOTE: This is actually a PowerShell script (export_result.ps1)
# In the real environment, this should be saved as export_result.ps1

<#
.SYNOPSIS
    Export script for save_diagnostic_views task
#>

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting task results ==="

$taskEnd = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$taskStart = 0
if (Test-Path "C:\tmp\task_start_time.txt") {
    $taskStart = Get-Content "C:\tmp\task_start_time.txt"
}

$outputDir = "C:\Users\Docker\Documents\CasePresentation"
$expectedFiles = @("panoramic_view.png", "axial_view.png", "3d_rendering_view.png", "cross_section_view.png")

$results = @{}
$results["task_start"] = $taskStart
$results["task_end"] = $taskEnd
$results["files"] = @{}

$allFilesExist = $true
$anyFileCreatedDuringTask = $false

foreach ($file in $expectedFiles) {
    $path = Join-Path $outputDir $file
    $fileInfo = @{
        "exists" = $false
        "size" = 0
        "created_during_task" = $false
    }
    
    if (Test-Path $path) {
        $item = Get-Item $path
        $fileInfo["exists"] = $true
        $fileInfo["size"] = $item.Length
        
        # Check creation/write time
        $mtime = [DateTimeOffset]::new($item.LastWriteTime).ToUnixTimeSeconds()
        $ctime = [DateTimeOffset]::new($item.CreationTime).ToUnixTimeSeconds()
        
        if ($mtime -gt $taskStart -or $ctime -gt $taskStart) {
            $fileInfo["created_during_task"] = $true
            $anyFileCreatedDuringTask = $true
        }
    } else {
        $allFilesExist = $false
    }
    
    $results["files"][$file] = $fileInfo
}

$results["all_files_exist"] = $allFilesExist
$results["any_activity_detected"] = $anyFileCreatedDuringTask

# Check if App is running
$proc = Get-Process "BlueSkyPlan" -ErrorAction SilentlyContinue
$results["app_running"] = [bool]$proc

# Take final screenshot
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Width, $screen.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    
    $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
    $bitmap.Save("C:\tmp\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
    
    $graphics.Dispose()
    $bitmap.Dispose()
    $results["screenshot_path"] = "C:\tmp\task_final.png"
} catch {
    Write-Warning "Failed to capture final screenshot"
    $results["screenshot_path"] = $null
}

# Convert to JSON and save
$json = $results | ConvertTo-Json -Depth 4
$json | Out-File "C:\tmp\task_result.json" -Encoding ascii

Write-Host "Result saved to C:\tmp\task_result.json"
Write-Host "=== Export Complete ==="