# Note: The environment uses PowerShell hooks, but we provide this file as setup_task.ps1 content
# The framework will execute the command defined in task.json.
# Below is the content for C:\workspace\tasks\validate_outbreak_temporal_logic\setup_task.ps1

Write-Host "=== Setting up Validate Outbreak Temporal Logic Task ==="

# 1. Define Paths
$DocPath = "C:\Users\Docker\Documents\EpiInfoData"
$CsvPath = "$DocPath\Ebola_Check.csv"
$TimestampPath = "C:\tmp\task_start_time.txt"

# 2. Create Directory
if (-not (Test-Path -Path $DocPath)) {
    New-Item -ItemType Directory -Path $DocPath -Force | Out-Null
}

# 3. Generate Synthetic Data with Specific Errors
Write-Host "Generating dataset at $CsvPath..."

$csvContent = "GlobalID,DateExposure,DateOnset,DateReport,Age,Sex,Outcome`n"
$startDate = Get-Date -Date "2023-01-01"

# Generate 150 records
for ($i = 1; $i -le 150; $i++) {
    $id = "CASE_{0:D3}" -f $i
    $isError = $false
    
    # Base dates (valid)
    $exposureDays = Get-Random -Minimum 0 -Maximum 60
    $incubation = Get-Random -Minimum 2 -Maximum 21
    $reportDelay = Get-Random -Minimum 1 -Maximum 5
    
    $dateExp = $startDate.AddDays($exposureDays)
    $dateOnset = $dateExp.AddDays($incubation)
    $dateReport = $dateOnset.AddDays($reportDelay)
    
    # Inject Specific Errors based on metadata
    # CASE_015: Onset before Exposure
    if ($id -eq "CASE_015") {
        $dateOnset = $dateExp.AddDays(-5) 
        $isError = $true
    }
    # CASE_042: Report before Onset
    elseif ($id -eq "CASE_042") {
        $dateReport = $dateOnset.AddDays(-3)
        $isError = $true
    }
    # CASE_088: Onset before Exposure (Extreme)
    elseif ($id -eq "CASE_088") {
        $dateOnset = $dateExp.AddDays(-10)
        $isError = $true
    }
    # CASE_101: Report before Onset
    elseif ($id -eq "CASE_101") {
        $dateReport = $dateOnset.AddDays(-1)
        $isError = $true
    }

    # Format dates MM/dd/yyyy for Epi Info
    $strExp = $dateExp.ToString("MM/dd/yyyy")
    $strOnset = $dateOnset.ToString("MM/dd/yyyy")
    $strReport = $dateReport.ToString("MM/dd/yyyy")
    
    $age = Get-Random -Minimum 18 -Maximum 80
    $sex = if ((Get-Random) % 2 -eq 0) { "M" } else { "F" }
    $outcome = if ((Get-Random) % 2 -eq 0) { "Recovered" } else { "Died" }

    $csvContent += "$id,$strExp,$strOnset,$strReport,$age,$sex,$outcome`n"
}

$csvContent | Out-File -FilePath $CsvPath -Encoding ASCII

# 4. Clean up previous results
$ResultPath = "$DocPath\Temporal_Errors.html"
if (Test-Path $ResultPath) {
    Remove-Item $ResultPath -Force
}

# 5. Record Start Time (Anti-gaming)
$epoch = [Math]::Floor((New-TimeSpan -Start (Get-Date "01/01/1970") -End (Get-Date)).TotalSeconds)
New-Item -ItemType File -Path $TimestampPath -Force -Value $epoch | Out-Null

# 6. Start Epi Info 7 Classic Analysis
Write-Host "Starting Epi Info 7 Classic Analysis..."
# Assume path based on standard installation in this env
$EpiPath = "C:\Epi_Info_7\Analysis.exe" 
# Fallback paths if env differs
if (-not (Test-Path $EpiPath)) { $EpiPath = "C:\Program Files (x86)\CDC\Epi Info 7\Analysis.exe" }

if (Test-Path $EpiPath) {
    Start-Process -FilePath $EpiPath -WindowStyle Maximized
} else {
    Write-Host "WARNING: Epi Info executable not found at standard locations."
}

# 7. Initial Screenshot
Start-Sleep -Seconds 5
# Powershell screenshot command (using specific tool if avail, or Python fallback)
# In this env, we rely on the framework to take the screenshot after the hook, 
# but we can try to force focus.
$wsh = New-Object -ComObject WScript.Shell
$wsh.SendKeys("%{TAB}") # Focus window

Write-Host "=== Setup Complete ==="