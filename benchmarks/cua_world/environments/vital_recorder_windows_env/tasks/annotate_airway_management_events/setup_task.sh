# setup_task.ps1 (Powershell)

Write-Host "=== Setting up Annotate Airway Management Task ==="

# Define paths
$DocumentsPath = "C:\Users\Docker\Documents"
$VitalDBPath = "$DocumentsPath\VitalDB"
$CaseFile = "$VitalDBPath\case_0006.vital"
$VitalRecorderPath = "C:\Program Files\VitalRecorder\VitalRecorder.exe"
$StartTimeFile = "C:\Users\Docker\Documents\task_start_time.txt"

# Create VitalDB directory if it doesn't exist
if (-not (Test-Path -Path $VitalDBPath)) {
    New-Item -ItemType Directory -Path $VitalDBPath | Out-Null
}

# Ensure the case file exists (Download if missing)
if (-not (Test-Path -Path $CaseFile)) {
    Write-Host "Downloading VitalDB Case #6..."
    $Url = "https://api.vitaldb.net/cases/6.vital" # Direct download URL for VitalDB cases
    # Note: If direct URL isn't stable, we would rely on pre-loaded data in the image.
    # Assuming pre-loaded or downloadable:
    try {
        Invoke-WebRequest -Uri "https://vitaldb.net/api/cases/6/vital" -OutFile $CaseFile
    } catch {
        Write-Host "Failed to download case file. Checking for local backup..."
        # Fallback to a sample if real download fails, assuming env has data
        if (Test-Path "C:\workspace\data\case_0006.vital") {
            Copy-Item "C:\workspace\data\case_0006.vital" $CaseFile
        } else {
            Write-Error "CRITICAL: Case data not found."
            exit 1
        }
    }
}

# Record start time for anti-gaming
$UnixTime = [int][double]::Parse((Get-Date -UFormat %s))
Set-Content -Path $StartTimeFile -Value $UnixTime

# Stop any running Vital Recorder instances
Stop-Process -Name "VitalRecorder" -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2

# Start Vital Recorder and load the case
Write-Host "Starting Vital Recorder with Case #6..."
Start-Process -FilePath $VitalRecorderPath -ArgumentList "`"$CaseFile`""
Start-Sleep -Seconds 10

# Ensure window is maximized (via naive keypress or relying on default behavior)
# Vital Recorder usually remembers last state, but we can try to force it via WScript if needed.
$wshell = New-Object -ComObject WScript.Shell
$wshell.AppActivate("Vital Recorder")
Start-Sleep -Milliseconds 500
# Alt+Space, X to maximize (standard Windows shortcut)
$wshell.SendKeys("% n") 
Start-Sleep -Milliseconds 500
$wshell.SendKeys("% x")

Write-Host "=== Setup Complete ==="