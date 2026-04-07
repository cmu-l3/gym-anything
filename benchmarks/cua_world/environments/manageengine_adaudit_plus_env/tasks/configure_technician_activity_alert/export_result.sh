# Note: This is a PowerShell script saved with a .ps1 extension in the environment.
# We present it here as export_result.ps1 content.

$ErrorActionPreference = "Continue"
Write-Host "=== Exporting Task Results ==="

# 1. timestamps
$taskEndTime = [int][double]::Parse((Get-Date -UFormat %s))
if (Test-Path "C:\Windows\Temp\task_start_time.txt") {
    $taskStartTime = Get-Content "C:\Windows\Temp\task_start_time.txt"
} else {
    $taskStartTime = 0
}

# 2. Check if Application is still running
$appRunning = $false
if (Get-Process "wrapper" -ErrorAction SilentlyContinue) { $appRunning = $true } # Java wrapper
if (Get-Process "msedge" -ErrorAction SilentlyContinue) { $appRunning = $true }

# 3. Attempt to capture final screenshot (PowerShell method)
# Note: In some Windows container envs, screen capture might be limited.
# We attempt it using .NET classes if available.
$screenshotPath = "C:\Windows\Temp\task_final.png"
$screenshotExists = $false

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $bmp.Save($screenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bmp.Dispose()
    $screenshotExists = $true
    Write-Host "Screenshot captured at $screenshotPath"
} catch {
    Write-Host "Failed to capture screenshot: $_"
}

# 4. Create Result JSON
$resultObject = @{
    task_start = $taskStartTime
    task_end = $taskEndTime
    app_was_running = $appRunning
    screenshot_exists = $screenshotExists
    screenshot_path = $screenshotPath
}

$jsonContent = $resultObject | ConvertTo-Json
Set-Content -Path "C:\Windows\Temp\task_result.json" -Value $jsonContent

Write-Host "Result saved to C:\Windows\Temp\task_result.json"
Write-Host $jsonContent
Write-Host "=== Export Complete ==="