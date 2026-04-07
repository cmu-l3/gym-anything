<#
.SYNOPSIS
    Setup script for update_facility_access_info task (PowerShell).
    Restores a clean database state and ensures CAMEO Data Manager is running.
#>

$ErrorActionPreference = "Stop"

Write-Host "=== Setting up Task: Update Facility Access Info ==="

# 1. Timestamp for anti-gaming
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path "C:\Users\Docker\Documents\task_start_time.txt" -Value $startTime

# 2. Kill existing CAMEO instances to ensure clean start
Write-Host "Terminating existing CAMEO instances..."
Stop-Process -Name "CAMEOfm" -ErrorAction SilentlyContinue
Stop-Process -Name "CAMEO" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# 3. Restore Database State (Simulated)
# In a real env, we would copy a .mer/.mdb file from a backup
$DataDir = "C:\Users\Docker\Documents\CAMEO\Data"
$BackupFile = "C:\workspace\data\Westside_Cold_Storage_Base.mer"
$TargetFile = "$DataDir\CAMEOfm.mer"

if (Test-Path $BackupFile) {
    Write-Host "Restoring base database..."
    Copy-Item -Path $BackupFile -Destination $TargetFile -Force
} else {
    Write-Host "WARNING: Base database not found. Using existing state."
}

# 4. Start CAMEO Data Manager
Write-Host "Starting CAMEO Data Manager..."
$CameoPath = "C:\Program Files (x86)\CAMEO Data Manager\CAMEOfm.exe"
if (-not (Test-Path $CameoPath)) {
    # Fallback path
    $CameoPath = "C:\Program Files\CAMEO Data Manager\CAMEOfm.exe"
}

if (Test-Path $CameoPath) {
    Start-Process -FilePath $CameoPath -WorkingDirectory (Split-Path $CameoPath)
} else {
    Write-Host "ERROR: CAMEO executable not found!"
    exit 1
}

# 5. Wait for Window and Maximize (using internal helper or generic approach)
# Since we don't have wmctrl easily in pure PS without external tools, 
# we rely on the environment's window manager or simple wait.
Start-Sleep -Seconds 10

# Attempt to activate window (simulated via simple shell script if needed, 
# but usually the agent handles focus. We just ensure it's running.)
Write-Host "Application started."

# 6. Take Initial Screenshot
# Using a PowerShell one-liner to capture screen (requires .NET System.Windows.Forms)
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$bmp = New-Object System.Drawing.Bitmap([System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width, [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height)
$graphics = [System.Drawing.Graphics]::FromImage($bmp)
$graphics.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
$bmp.Save("C:\Users\Docker\Documents\task_initial.png", [System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bmp.Dispose()

Write-Host "=== Setup Complete ==="