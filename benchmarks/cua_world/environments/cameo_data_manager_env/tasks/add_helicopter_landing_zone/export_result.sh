# Note: This is a PowerShell script saved with .ps1 extension in the environment
# Filename: export_result.ps1

$ErrorActionPreference = "Stop"
Write-Host "=== Exporting Task Results ==="

$tmpDir = "C:\tmp"
$resultJsonPath = "$tmpDir\task_result.json"

# 1. Capture Task End Time
$endTime = Get-Date -UFormat %s

# 2. Check Database Modification
$dbPath = "C:\Users\Public\Documents\CAMEO Data Manager\CAMEO.mer"
$dbDir = "C:\Users\Public\Documents\CAMEO Data Manager"
$dbModified = $false
$lastWriteTime = 0

if (Test-Path $dbPath) {
    $item = Get-Item $dbPath
    $lastWriteTime = $item.LastWriteTime.Ticks
} elseif (Test-Path $dbDir) {
    $item = Get-Item $dbDir
    $lastWriteTime = $item.LastWriteTime.Ticks
}

# Compare with initial
$initialTimestampPath = "$tmpDir\initial_db_timestamp.txt"
if (Test-Path $initialTimestampPath) {
    $initialTimestamp = Get-Content $initialTimestampPath
    if ([long]$lastWriteTime -gt [long]$initialTimestamp) {
        $dbModified = $true
    }
}

# 3. Check if App is Running
$appRunning = $false
if (Get-Process -Name "CAMEOdm" -ErrorAction SilentlyContinue) {
    $appRunning = $true
}

# 4. Capture Final Screenshot (PowerShell method)
# Requires System.Windows.Forms and System.Drawing
$screenshotPath = "$tmpDir\task_final.png"
try {
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    
    $screen = [System.Windows.Forms.Screen]::PrimaryScreen
    $bitmap = New-Object System.Drawing.Bitmap $screen.Bounds.Width, $screen.Bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($screen.Bounds.X, $screen.Bounds.Y, 0, 0, $bitmap.Size)
    
    $bitmap.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-Host "Screenshot saved to $screenshotPath"
} catch {
    Write-Host "Failed to capture screenshot: $_"
}

# 5. Create JSON Result
$resultObject = @{
    task_end_timestamp = $endTime
    db_file_modified   = $dbModified
    app_running        = $appRunning
    screenshot_path    = $screenshotPath
    db_path_checked    = if (Test-Path $dbPath) { $dbPath } else { $dbDir }
}

$resultObject | ConvertTo-Json | Out-File -FilePath $resultJsonPath -Encoding ascii

Write-Host "Result saved to $resultJsonPath"
Write-Host "=== Export Complete ==="