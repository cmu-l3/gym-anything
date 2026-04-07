<#
.SYNOPSIS
    Export script for update_facility_access_info task (PowerShell).
    Captures final state, verifies file modification, and searches DB content.
#>

$ErrorActionPreference = "Continue" # Don't stop on minor errors

Write-Host "=== Exporting Task Results ==="

# Paths
$DataFile = "C:\Users\Docker\Documents\CAMEO\Data\CAMEOfm.mer" # Assuming standard path
$ResultJson = "C:\Users\Docker\Documents\task_result.json"
$ScreenshotPath = "C:\Users\Docker\Documents\task_final.png"
$StartTimeFile = "C:\Users\Docker\Documents\task_start_time.txt"

# 1. Capture Final Screenshot
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($ScreenshotPath, [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()

# 2. Check File Modification
$DbModified = $false
$DbSizeBytes = 0
$TaskStartTime = 0

if (Test-Path $StartTimeFile) {
    $TaskStartTime = Get-Content $StartTimeFile
}

if (Test-Path $DataFile) {
    $Item = Get-Item $DataFile
    $DbSizeBytes = $Item.Length
    # Convert LastWriteTime to Unix timestamp
    $ModTime = [int][double]::Parse((Get-Date $Item.LastWriteTime -UFormat %s))
    
    if ($ModTime -gt $TaskStartTime) {
        $DbModified = $true
    }
}

# 3. Search for Strings in Database File (Binary Search)
# We read the file as text (Latin1/Default) to find the inserted strings.
# This is a heuristic; CAMEO files might be binary but text often remains readable.
$ContentFound = @{
    "KeyLocation" = $false
    "SiteAccess" = $false
    "Security" = $false
    "GateCode" = $false
}

if (Test-Path $DataFile) {
    # Read file content safely (could be large, read reasonable chunk or use Select-String)
    # Using Select-String with -Encoding default might work for .mer files if they aren't compressed
    
    if (Select-String -Path $DataFile -Pattern "Knox Box 3200" -Quiet -Encoding default) { $ContentFound["KeyLocation"] = $true }
    if (Select-String -Path $DataFile -Pattern "North Service Road" -Quiet -Encoding default) { $ContentFound["SiteAccess"] = $true }
    if (Select-String -Path $DataFile -Pattern "Night watchman" -Quiet -Encoding default) { $ContentFound["Security"] = $true }
    if (Select-String -Path $DataFile -Pattern "7721#" -Quiet -Encoding default) { $ContentFound["GateCode"] = $true }
}

# 4. Check if App is Running
$AppRunning = [bool](Get-Process "CAMEOfm" -ErrorAction SilentlyContinue)

# 5. Export to JSON
$Result = @{
    "db_modified" = $DbModified
    "db_size_bytes" = $DbSizeBytes
    "app_running" = $AppRunning
    "content_found" = $ContentFound
    "screenshot_path" = $ScreenshotPath
    "timestamp" = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

$Result | ConvertTo-Json | Set-Content -Path $ResultJson

Write-Host "Result exported to $ResultJson"
Get-Content $ResultJson