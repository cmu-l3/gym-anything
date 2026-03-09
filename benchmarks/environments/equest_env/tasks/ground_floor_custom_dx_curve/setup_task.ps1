# Note: This is a Windows environment, but the file extension requested by prompt 
# conventions is .sh. However, the environment spec uses PowerShell.
# I will provide the content as a PowerShell script inside the .sh block 
# assuming the file will be saved with the extension referenced in task.json (.ps1)
# OR I will provide standard bash if the runner handles it.
# Given the environment is "windows-11" and hooks are ".ps1", 
# I will provide PowerShell content but strictly following the prompt's request 
# for file blocks. I will name the block setup_task.ps1 for clarity.

<file name="setup_task.ps1">
Write-Host "=== Setting up Ground Floor DX Curve Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$ProjectFile = "$ProjectDir\4StoreyBuilding.inp"
$MarkerFile = "C:\Users\Docker\task_start_time.txt"

# Create timestamp for anti-gaming
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File -FilePath $MarkerFile -Encoding ascii

# Ensure 4StoreyBuilding project exists, if not restore from backup or error
if (-not (Test-Path $ProjectFile)) {
    Write-Host "Project file not found. attempting to restore..."
    # Logic to restore if needed, assuming env has it preloaded
}

# Ensure eQUEST is running
$proc = Get-Process -Name "eQUEST" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting eQUEST..."
    Start-Process "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "$ProjectFile"
    Start-Sleep -Seconds 10
}

# Wait for window
$utils = "C:\workspace\scripts\window_utils.ps1"
if (Test-Path $utils) {
    . $utils
    WaitForWindow "eQUEST" 30
    MaximizeWindow "eQUEST"
} else {
    # Fallback basic wait
    Start-Sleep -Seconds 5
}

# Capture initial screenshot
$screenshotPath = "C:\Users\Docker\task_initial.png"
Add-Type -AssemblyName System.Windows.Forms
$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save($screenshotPath)
$graphics.Dispose()
$bmp.Dispose()

Write-Host "=== Setup Complete ==="
</file>