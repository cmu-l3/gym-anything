# export_result.ps1 (Powershell script for Windows environment)
$ErrorActionPreference = "Continue"

Write-Host "=== Exporting Task Results ==="

# Define paths
$ProjectDir = "C:\Users\Docker\Documents\eQUEST 3-65 Projects\4StoreyBuilding"
$InpFile = "$ProjectDir\4StoreyBuilding.inp"
$SimFile = "$ProjectDir\4StoreyBuilding.sim"
$ResultJson = "C:\Users\Docker\south_window_overhangs_result.json"
$StartTimeFile = "C:\Users\Docker\task_start_time.txt"

# Get Task Start Time
if (Test-Path $StartTimeFile) {
    $TaskStart = Get-Content $StartTimeFile
} else {
    $TaskStart = 0
}

# Check Simulation File
$SimExists = $false
$SimIsNew = $false
if (Test-Path $SimFile) {
    $SimExists = $true
    $SimInfo = Get-Item $SimFile
    $SimTime = [int64]($SimInfo.LastWriteTime.ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
    
    if ($SimTime -gt $TaskStart) {
        $SimIsNew = $true
    }
}

# Check INP File modification
$InpExists = $false
$InpIsModified = $false
if (Test-Path $InpFile) {
    $InpExists = $true
    $InpInfo = Get-Item $InpFile
    $InpTime = [int64]($InpInfo.LastWriteTime.ToUniversalTime() - (Get-Date "1/1/1970")).TotalSeconds
    
    if ($InpTime -gt $TaskStart) {
        $InpIsModified = $true
    }
}

# Create JSON Result
$ResultObject = @{
    task_start_time = $TaskStart
    sim_file_exists = $SimExists
    sim_file_is_new = $SimIsNew
    inp_file_exists = $InpExists
    inp_file_modified = $InpIsModified
    project_path = $InpFile
    timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

$ResultObject | ConvertTo-Json | Set-Content $ResultJson

Write-Host "Result JSON saved to $ResultJson"
Get-Content $ResultJson