# setup_task.ps1 (Powershell)
Write-Host "=== Setting up Top Floor Atrium Skylight Task ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$ProjectFile = "$ProjectDir\4StoreyBuilding.inp"
$TaskStartTimeFile = "C:\Users\Docker\task_start_time.txt"

# 1. Create timestamp for anti-gaming verification
$startTime = [int][double]::Parse((Get-Date -UFormat %s))
$startTime | Out-File -FilePath $TaskStartTimeFile -Encoding ASCII
Write-Host "Task start time recorded: $startTime"

# 2. Ensure eQUEST is running with the project
$eQuestProcess = Get-Process -Name "equest" -ErrorAction SilentlyContinue

if (-not $eQuestProcess) {
    Write-Host "Starting eQUEST..."
    # Start eQUEST and open the project file
    Start-Process -FilePath "C:\Program Files (x86)\eQUEST 3-65\eQUEST.exe" -ArgumentList "`"$ProjectFile`"" -WindowStyle Maximized
    
    # Wait for the application to load
    Write-Host "Waiting for eQUEST to load..."
    Start-Sleep -Seconds 15
} else {
    Write-Host "eQUEST is already running."
}

# 3. Focus and Maximize Window (using external tools or simple powershell focus)
# Note: In this env, we rely on the agent or basic window management. 
# We'll try to ensure it's foreground using a simple shell object.
$wshell = New-Object -ComObject wscript.shell
$wshell.AppActivate("eQUEST")
Start-Sleep -Seconds 1

# 4. Take Initial Screenshot
Write-Host "Taking initial screenshot..."
Get-Screenshot -Path "C:\Users\Docker\task_initial.png"

Write-Host "=== Task Setup Complete ==="