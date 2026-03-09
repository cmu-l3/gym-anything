# Note: The environment uses PowerShell for Windows tasks, but the framework expects a shell script entry point if defined as .sh.
# However, the env definition shows "hooks": "powershell ...".
# Based on the previous examples for this env, the hooks are defined as powershell commands in task.json.
# I will provide the content as a PowerShell script since the environment is Windows.
# The filename in the code block will be setup_task.ps1 to match the hook in task.json.

Write-Host "=== Setting up Configure Hot Keys Task ==="

# 1. Define paths
$ConfigDir = "C:\Users\Docker\Documents\NinjaTrader 8\config"
$TaskDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$StartTimeFile = "C:\tmp\task_start_time.txt"

# 2. Create directories
New-Item -ItemType Directory -Force -Path $TaskDir | Out-Null
New-Item -ItemType Directory -Force -Path "C:\tmp" | Out-Null

# 3. Record start time (Unix timestamp)
$epoch = Get-Date -Date "01/01/1970"
$current = Get-Date
$timestamp = [math]::Round(($current - $epoch).TotalSeconds)
$timestamp | Out-File -FilePath $StartTimeFile -Encoding ascii

# 4. Snapshot initial config state (filenames and last write times)
$InitialConfigState = Get-ChildItem -Path $ConfigDir -Filter "*.xml" | Select-Object Name, LastWriteTime
$InitialConfigState | Export-Csv -Path "C:\tmp\initial_config_state.csv" -NoTypeInformation

# 5. Start NinjaTrader if not running
$ntProcess = Get-Process -Name "NinjaTrader" -ErrorAction SilentlyContinue
if (-not $ntProcess) {
    Write-Host "Starting NinjaTrader..."
    Start-Process -FilePath "C:\Program Files\NinjaTrader 8\bin\NinjaTrader.exe"
    
    # Wait for UI
    $loops = 0
    while ($loops -lt 30) {
        $proc = Get-Process -Name "NinjaTrader" -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowTitle) {
            Write-Host "NinjaTrader window detected."
            break
        }
        Start-Sleep -Seconds 2
        $loops++
    }
} else {
    Write-Host "NinjaTrader is already running."
}

# 6. Ensure window is maximized (simple attempt via separate utility or powershell assumption)
# In this env, we rely on the agent or basic window state. 
# We can try to focus it.
$wshell = New-Object -ComObject wscript.shell
if ($wshell.AppActivate("NinjaTrader")) {
    Start-Sleep -Milliseconds 500
    # Send Alt+Space, X to maximize (standard Windows shortcut)
    # $wshell.SendKeys("% x") 
}

# 7. Close any existing Chart/Analyzer windows to ensure clean slate for testing
# (Optional, but helps verify if agent actually opens new ones)

Write-Host "=== Setup Complete ==="