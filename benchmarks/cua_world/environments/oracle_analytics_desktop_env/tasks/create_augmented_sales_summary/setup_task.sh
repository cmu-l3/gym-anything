# Note: This environment uses PowerShell. The hook points to a .ps1 file.
# However, for consistency with the file generation request, I am providing the content
# that should go into 'setup_task.ps1' within the Windows environment.
# Since the prompt asks for 'setup_task.sh', I will provide the PowerShell code
# inside the setup_task.ps1 file block below.

# FILE: setup_task.ps1
Write-Host "=== Setting up Augmented Sales Summary Task ==="

# 1. Setup paths and clean previous state
$docPath = "C:\Users\Docker\Documents"
$dvaPath = "$docPath\Augmented_Summary.dva"
$startTimePath = "C:\Temp\task_start_time.txt"

if (Test-Path $dvaPath) {
    Write-Host "Removing previous output file..."
    Remove-Item $dvaPath -Force
}

# Ensure temp dir exists
if (-not (Test-Path "C:\Temp")) {
    New-Item -ItemType Directory -Force -Path "C:\Temp"
}

# 2. Record start time (Unix timestamp)
$startTime = [int64]((Get-Date) - (Get-Date "1/1/1970")).TotalSeconds
Set-Content -Path $startTimePath -Value $startTime

# 3. Ensure Oracle Analytics Desktop is running
$proc = Get-Process "Oracle Analytics Desktop" -ErrorAction SilentlyContinue
if (-not $proc) {
    Write-Host "Starting Oracle Analytics Desktop..."
    Start-Process "C:\Program Files\Oracle Analytics Desktop\Oracle Analytics Desktop.exe"
    Start-Sleep -Seconds 15
}

# 4. Wait for window and maximize (using naive approach or relying on agent)
# In this env, we rely on the agent finding the window, but we can try to bring it to front
# via simple powershell script if WScript.Shell is available.
try {
    $wshell = New-Object -ComObject WScript.Shell
    $wshell.AppActivate("Oracle Analytics Desktop")
    Start-Sleep -Milliseconds 500
    # Send Alt+Space, x to maximize (standard Windows shortcut)
    $wshell.SendKeys("% n") 
} catch {
    Write-Host "Could not focus window programmatically."
}

# 5. Capture initial screenshot (if screenshot tool available in env)
# Assuming a screenshot tool or relying on framework periodic capture.
# This step is often handled by the framework in Windows envs, but we'll leave a placeholder.
Write-Host "Setup complete."