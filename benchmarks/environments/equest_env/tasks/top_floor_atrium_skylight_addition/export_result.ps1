# export_result.ps1 (Powershell)
Write-Host "=== Exporting Task Results ==="

$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$SimFile = "$ProjectDir\4StoreyBuilding.SIM"
$TaskStartTimeFile = "C:\Users\Docker\task_start_time.txt"
$ResultJson = "C:\Users\Docker\task_result.json"

# 1. Take Final Screenshot
Write-Host "Taking final screenshot..."
Get-Screenshot -Path "C:\Users\Docker\task_final.png"

# 2. Check Simulation Timestamp
$simExists = Test-Path $SimFile
$simNew = $false
$simTime = 0

if (Test-Path $TaskStartTimeFile) {
    $startTime = [int](Get-Content $TaskStartTimeFile)
} else {
    $startTime = 0
}

if ($simExists) {
    $fileInfo = Get-Item $SimFile
    $simTime = [int][double]::Parse(($fileInfo.LastWriteTime -UFormat %s))
    
    if ($simTime -gt $startTime) {
        $simNew = $true
        Write-Host "Simulation file was updated during the task."
    } else {
        Write-Host "Simulation file is older than task start."
    }
} else {
    Write-Host "Simulation output file not found."
}

# 3. Check if eQUEST is running
$appRunning = [bool](Get-Process -Name "equest" -ErrorAction SilentlyContinue)

# 4. Create Result JSON
# We only export simulation status here; complex INP parsing happens in verifier.py
$resultObject = @{
    sim_file_exists = $simExists
    sim_file_is_new = $simNew
    sim_timestamp = $simTime
    app_was_running = $appRunning
    task_start_time = $startTime
    screenshot_path = "C:\Users\Docker\task_final.png"
}

$resultObject | ConvertTo-Json | Out-File -FilePath $ResultJson -Encoding ASCII

Write-Host "Result exported to $ResultJson"
Type $ResultJson