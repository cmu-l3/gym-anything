# Note: This is actually a PowerShell script (export_result.ps1)
# The task.json refers to it as export_result.ps1

$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== Exporting Task Results ==="

# 1. Capture Final Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screen = [System.Windows.Forms.Screen]::PrimaryScreen
$bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
$bitmap.Save("C:\workspace\task_final.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()

# 2. Check Database File Modification
# CAMEO typically stores data in "C:\Users\Public\Documents\CAMEO Data Manager\CAMEO.mer" 
# or similar user/public document paths.
$dbPaths = @(
    "C:\Users\Public\Documents\CAMEO Data Manager\CAMEO.mer",
    "C:\Users\Docker\Documents\CAMEO Data Manager\CAMEO.mer",
    "C:\CAMEOfm\CAMEO.mer"
)

$dbModified = $false
$lastWriteTime = 0
$taskStartTime = 0

if (Test-Path "C:\workspace\task_start_time.txt") {
    $taskStartTime = Get-Content "C:\workspace\task_start_time.txt"
}

foreach ($path in $dbPaths) {
    if (Test-Path $path) {
        $item = Get-Item $path
        # Convert DateTime to Unix timestamp
        $modTime = [int64]($item.LastWriteTime.ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
        
        if ($modTime -gt $taskStartTime) {
            $dbModified = $true
            $lastWriteTime = $modTime
            Write-Host "Database file modified: $path"
            break
        }
    }
}

# 3. Check if App is Running
$appRunning = $false
if (Get-Process "CAMEOfm" -ErrorAction SilentlyContinue) {
    $appRunning = $true
}

# 4. Create Result JSON
$json = @{
    "task_start" = $taskStartTime
    "db_modified" = $dbModified
    "app_running" = $appRunning
    "screenshot_path" = "C:\workspace\task_final.png"
    "timestamp" = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ss")
}

$jsonString = $json | ConvertTo-Json
$jsonString | Out-File -FilePath "C:\workspace\task_result.json" -Encoding ASCII

Write-Host "Result exported to C:\workspace\task_result.json"