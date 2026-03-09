# setup_task.ps1 (Powershell script for Windows environment)
$ErrorActionPreference = "Stop"

Write-Host "=== Setting up South Window Overhangs Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$SimFile = "$ProjectDir\4StoreyBuilding.sim"

# Record task start timestamp (Unix epoch)
$startTime = [int64]((Get-Date).ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
Set-Content -Path "C:\Users\Docker\task_start_time.txt" -Value $startTime

# Ensure clean state: Remove previous simulation results if any
if (Test-Path $SimFile) {
    Remove-Item $SimFile -Force
    Write-Host "Removed previous simulation results."
}

# Ensure eQUEST is running with the project
$process = Get-Process "eQUEST" -ErrorAction SilentlyContinue
if (-not $process) {
    Write-Host "Starting eQUEST..."
    # Start eQUEST and open the project file
    Start-Process "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "`"$InpFile`""
    
    # Wait for the window to appear
    $timeout = 60
    $timer = 0
    while ($timer -lt $timeout) {
        if (Get-Process "eQUEST" -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like "*4StoreyBuilding*" }) {
            Write-Host "eQUEST window detected."
            break
        }
        Start-Sleep -Seconds 1
        $timer++
    }
}

# Maximize the window (using nircmd or similar if available, otherwise just rely on default)
# In this environment, we assume the user/agent will interact with the window.
# We can try to bring it to front.
$wshell = New-Object -ComObject wscript.shell
if ($wshell.AppActivate("eQUEST")) {
    Start-Sleep -Milliseconds 500
    # Send Alt+Space, x to maximize (standard Windows shortcut)
    $wshell.SendKeys("% n") 
}

# Take initial screenshot using python or available tool in env
# Assuming standard screenshot tool is available or skipped if not
Write-Host "Setup complete."