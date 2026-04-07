# NOTE: This is actually a PowerShell script (setup_task.ps1) to be run on Windows
# The file extension is kept as .ps1 in the content below, but labeled as requested.
# To function correctly in the Windows env, save this as `setup_task.ps1`.

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Blend Sales Targets Task ==="

# Define paths
$DocPath = "C:\Users\Docker\Documents"
if (-not (Test-Path $DocPath)) { New-Item -ItemType Directory -Path $DocPath -Force }

$CsvPath = "$DocPath\Regional_Targets.csv"
$DvaPath = "$DocPath\Regional_Performance.dva"
$TimestampPath = "$env:TEMP\task_start_time.txt"

# 1. Create Real Data (CSV)
# Real-world messiness: None here, clean data for joining
$csvContent = @"
Region,Target
Central,5000000
East,6000000
South,4500000
West,8500000
"@
Set-Content -Path $CsvPath -Value $csvContent
Write-Host "Created target data file at $CsvPath"

# 2. Cleanup old results to prevent false positives
if (Test-Path $DvaPath) { 
    Remove-Item $DvaPath -Force 
    Write-Host "Removed stale result file"
}

# 3. Record Start Time (Epoch seconds) for anti-gaming
$startTime = [int64]((Get-Date).ToUniversalTime() - [DateTime]::UnixEpoch).TotalSeconds
Set-Content -Path $TimestampPath -Value $startTime
Write-Host "Task start time recorded: $startTime"

# 4. Ensure Application is Running
# Check for "DVD" process (Oracle Analytics Desktop often runs as DVD.exe or similar, depending on version)
# We'll check for the window title or process name
$proc = Get-Process "Oracle Analytics Desktop" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting Oracle Analytics Desktop..."
    # Attempt standard install path
    $OADPath = "C:\Program Files\Oracle Analytics Desktop\Oracle Analytics Desktop.exe"
    if (Test-Path $OADPath) {
        Start-Process $OADPath -WindowStyle Maximized
    } else {
        # Fallback to shortcut or desktop link if main path fails
        $Shortcut = Get-ChildItem "C:\Users\Public\Desktop\Oracle Analytics Desktop.lnk" -ErrorAction SilentlyContinue
        if ($Shortcut) {
            Start-Process $Shortcut.FullName
        } else {
            Write-Warning "Could not find OAD executable. Assuming it's in PATH or user will launch."
        }
    }
    
    # Wait for startup
    Start-Sleep -Seconds 15
} else {
    Write-Host "Application is already running."
}

# 5. Bring Window to Front (Basic attempt)
# PowerShell native window management is limited without external DLLs, 
# but starting the process usually focuses it.

Write-Host "=== Setup Complete ==="