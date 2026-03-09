#!/bin/bash
echo "=== Setting up Energy Transition Task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# We use PowerShell to interact with the Windows environment
# 1. Create Data Directory
# 2. Create the wide-format CSV file
# 3. Ensure Power BI is clean/ready

cat << 'EOF' > /tmp/setup_pbi.ps1
$DesktopPath = "C:\Users\Docker\Desktop"
$TaskDir = "$DesktopPath\PowerBITasks"
$CsvPath = "$TaskDir\energy_generation_wide.csv"
$ReportPath = "$DesktopPath\Energy_Transition.pbix"

# 1. Clean up previous runs
If (Test-Path $ReportPath) { Remove-Item $ReportPath -Force }
If (Test-Path $TaskDir) { Remove-Item $TaskDir -Recurse -Force }
New-Item -ItemType Directory -Force -Path $TaskDir | Out-Null

# 2. Generate Real-World Data (Wide Format)
$CsvContent = @"
Source,2010,2011,2012,2013,2014,2015,2016,2017,2018,2019,2020
Coal,980,960,940,920,900,850,800,750,700,600,500
Natural Gas,400,420,440,460,480,500,550,600,650,700,720
Nuclear,300,300,295,290,290,285,285,280,280,275,275
Hydro,250,255,245,260,265,260,270,275,280,285,290
Wind,40,55,70,95,120,150,190,240,300,380,450
Solar,5,10,20,35,55,80,120,170,230,300,390
Bioenergy,30,32,34,36,38,40,42,44,46,48,50
"@

Set-Content -Path $CsvPath -Value $CsvContent -Encoding UTF8
Write-Host "Created data at $CsvPath"

# 3. Reset Power BI
$PbiProcess = Get-Process PBIDesktop -ErrorAction SilentlyContinue
if ($PbiProcess) {
    Stop-Process -Name PBIDesktop -Force
    Start-Sleep -Seconds 2
}

# 4. Start Power BI Desktop
$PbiPath = "C:\Program Files\Microsoft Power BI Desktop\bin\PBIDesktop.exe"
if (Test-Path $PbiPath) {
    Start-Process $PbiPath
} else {
    # Fallback for Windows Store version or different path
    Start-Process "PBIDesktop"
}

Write-Host "Power BI Desktop started."
EOF

# Execute the PowerShell script
powershell -ExecutionPolicy Bypass -File /tmp/setup_pbi.ps1

# Wait for window to stabilize (simple sleep since we can't easily query Win32 windows from bash here)
sleep 15

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="