# Note: This is a PowerShell script saved with .ps1 extension in the environment
# Filename: setup_task.ps1

$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Add Helicopter Landing Zone Task ==="

# Create temp directory if it doesn't exist
$tmpDir = "C:\tmp"
if (-not (Test-Path $tmpDir)) {
    New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null
}

# 1. Record Start Time
$startTime = Get-Date -UFormat %s
$startTime | Out-File -FilePath "$tmpDir\task_start_time.txt" -Encoding ascii

# 2. Record Initial Database State (Timestamp)
# CAMEO usually stores data in C:\Users\Public\Documents\CAMEO Data Manager\ or similar
$dbPath = "C:\Users\Public\Documents\CAMEO Data Manager\CAMEO.mer"
# Fallback to checking the directory if specific file unknown
$dbDir = "C:\Users\Public\Documents\CAMEO Data Manager"

if (Test-Path $dbPath) {
    $item = Get-Item $dbPath
    $item.LastWriteTime.Ticks | Out-File -FilePath "$tmpDir\initial_db_timestamp.txt" -Encoding ascii
} elseif (Test-Path $dbDir) {
    # If specific file not found, monitor the directory
    $item = Get-Item $dbDir
    $item.LastWriteTime.Ticks | Out-File -FilePath "$tmpDir\initial_db_timestamp.txt" -Encoding ascii
} else {
    Write-Host "WARNING: CAMEO Database path not found at $dbPath"
    "0" | Out-File -FilePath "$tmpDir\initial_db_timestamp.txt" -Encoding ascii
}

# 3. Ensure CAMEO Data Manager is Running
$processName = "CAMEOdm"
if (-not (Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
    Write-Host "Starting CAMEO Data Manager..."
    # Common path, may vary based on installation in env
    $cameoExe = "C:\Program Files (x86)\CAMEO Data Manager\CAMEOdm.exe"
    
    if (Test-Path $cameoExe) {
        Start-Process -FilePath $cameoExe -WindowStyle Maximized
        
        # Wait for window
        $timeout = 30
        for ($i=0; $i -lt $timeout; $i++) {
            if (Get-Process -Name $processName -ErrorAction SilentlyContinue) {
                Write-Host "Process started."
                break
            }
            Start-Sleep -Seconds 1
        }
        Start-Sleep -Seconds 10 # Allow UI to load
    } else {
        Write-Error "CAMEO Executable not found at $cameoExe"
    }
} else {
    Write-Host "CAMEO is already running."
}

# 4. Bring Window to Front (basic attempt via PS)
# Note: Full window management in Windows containers is limited, relying on agent to click.
# But we can try to use WScript.Shell
try {
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.AppActivate("CAMEO Data Manager")
    Start-Sleep -Seconds 1
} catch {
    Write-Host "Could not focus window programmatically."
}

Write-Host "=== Setup Complete ==="