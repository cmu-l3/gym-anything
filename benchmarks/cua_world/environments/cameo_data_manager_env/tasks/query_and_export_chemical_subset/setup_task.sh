# Note: This is actually a PowerShell script saved with .ps1 extension in the environment
# But for the file generation output, we use the requested format.
# The filename in the header will be setup_task.ps1

<#
.SYNOPSIS
Setup script for Query and Export Task
#>

Write-Host "=== Setting up Query and Export Task ==="

# Define paths
$CameoPath = "C:\CAMEOfm\CAMEOfm.exe"
$DataDir = "C:\Users\Public\Documents\CAMEO Data Manager"
$SeedDB = "C:\workspace\data\query_task_seed.mer" 
$StartTimeFile = "C:\workspace\task_start_time.txt"

# 1. Record Start Time
$currentEpoch = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
$currentEpoch | Out-File -FilePath $StartTimeFile -Encoding ASCII

# 2. Clean previous outputs
Remove-Item "C:\Users\Docker\Documents\chlorine_facilities.csv" -ErrorAction SilentlyContinue
Remove-Item "C:\workspace\task_result.json" -ErrorAction SilentlyContinue

# 3. Prepare Database
# Kill CAMEO if running
Stop-Process -Name "CAMEOfm" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Check if we have the specific seed DB, otherwise warn (agent might still try with default DB)
if (Test-Path $SeedDB) {
    Write-Host "Restoring seed database..."
    Copy-Item $SeedDB "$DataDir\CAMEOfm.mer" -Force
} else {
    Write-Host "WARNING: Seed database not found at $SeedDB. Using current database."
}

# 4. Launch CAMEO Data Manager
Write-Host "Launching CAMEO Data Manager..."
Start-Process $CameoPath
Start-Sleep -Seconds 10

# 5. Window Management
Add-Type -AssemblyName System.Windows.Forms
[System.Windows.Forms.SendKeys]::SendWait("% x") # Alt+Space, x to maximize

# Ensure it's focused
$wshell = New-Object -ComObject wscript.shell
$wshell.AppActivate("CAMEO Data Manager")
Start-Sleep -Seconds 1

# 6. Take Initial Screenshot
# Using a simple powershell screenshot function or external tool if available
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$Screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
$Bitmap = New-Object System.Drawing.Bitmap $Screen.Width, $Screen.Height
$Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
$Graphics.CopyFromScreen($Screen.Left, $Screen.Top, 0, 0, $Bitmap.Size)
$Bitmap.Save("C:\workspace\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
$Graphics.Dispose()
$Bitmap.Dispose()

Write-Host "=== Task Setup Complete ==="