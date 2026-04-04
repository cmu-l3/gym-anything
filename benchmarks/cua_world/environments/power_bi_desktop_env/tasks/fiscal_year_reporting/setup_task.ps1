# Note: The environment expects a PowerShell script for pre_task based on the hooks definition.
# However, the framework standard is usually bash. For Windows environments in this framework,
# we often use a bash wrapper or direct PowerShell. 
# Below is the content for C:\workspace\tasks\fiscal_year_reporting\setup_task.ps1
# We will provide it in the format expected by the container (Powershell script).

<file name="setup_task.ps1">
$ErrorActionPreference = "Stop"
Write-Host "=== Setting up Fiscal Year Reporting Task ==="

# 1. Timestamp for anti-gaming
$startTime = [DateTimeOffset]::Now.ToUnixTimeSeconds()
$startTime | Out-File "C:\Users\Docker\Desktop\task_start_time.txt" -Encoding ascii

# 2. Cleanup previous runs
$desktopPath = "C:\Users\Docker\Desktop"
$taskDir = "$desktopPath\PowerBITasks"
if (!(Test-Path $taskDir)) { New-Item -ItemType Directory -Path $taskDir | Out-Null }

$outputFile = "$desktopPath\Fiscal_Report.pbix"
if (Test-Path $outputFile) { Remove-Item $outputFile -Force }

# 3. Generate Real-World Data (finance_data.csv)
Write-Host "Generating financial dataset..."
$csvPath = "$taskDir\finance_data.csv"

$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("Date,Revenue,Division")

$startDate = Get-Date -Date "2023-01-01"
$endDate = Get-Date -Date "2024-12-31"
$current = $startDate
$rng = [System.Random]::new()

while ($current -le $endDate) {
    # Add some seasonality (higher revenue in Q4)
    $baseRev = 1000
    if ($current.Month -ge 10) { $baseRev = 1500 }
    
    $dailyRev = $baseRev + $rng.Next(-200, 500)
    
    # 30% chance of Division A, 30% B, 40% C
    $r = $rng.NextDouble()
    if ($r -lt 0.3) { $div = "North" }
    elseif ($r -lt 0.6) { $div = "South" }
    else { $div = "Global" }
    
    $dateStr = $current.ToString("yyyy-MM-dd")
    [void]$sb.AppendLine("$dateStr,$dailyRev,$div")
    
    $current = $current.AddDays(1)
}

$sb.ToString() | Out-File $csvPath -Encoding ascii
Write-Host "Data generated at $csvPath"

# 4. Ensure Power BI is running and ready
$pbiProc = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
if (!$pbiProc) {
    Write-Host "Starting Power BI Desktop..."
    Start-Process "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
    
    # Wait for window
    $timeout = 60
    while ($timeout -gt 0) {
        $proc = Get-Process -Name "PBIDesktop" -ErrorAction SilentlyContinue
        if ($proc -and $proc.MainWindowTitle) {
            break
        }
        Start-Sleep -Seconds 1
        $timeout--
    }
}

Write-Host "=== Setup Complete ==="
</file>