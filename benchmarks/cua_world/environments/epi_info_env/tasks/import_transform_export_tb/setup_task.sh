#!/bin/bash
echo "=== Setting up Epi Info TB Data Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Create a temporary PowerShell script to handle Windows setup
# We use a heredoc to embed the PS1 content
cat << 'PS1EOF' > /tmp/setup_logic.ps1
$ErrorActionPreference = "Stop"

# 1. Prepare Directories
$DocPath = "C:\Users\Docker\Documents"
$DataDir = "$DocPath\TBData"
$OutputDir = "$DataDir\output"
New-Item -ItemType Directory -Force -Path $DataDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

# Clean up previous runs
If (Test-Path "$OutputDir\afr_tb_2015_2020.csv") {
    Remove-Item "$OutputDir\afr_tb_2015_2020.csv" -Force
}

# 2. Generate Realistic WHO TB Notification Data (Simulating Real Data)
# We generate this to ensure consistency and availability, matching real WHO schema
$CsvPath = "$DataDir\who_tb_notifications.csv"

$Header = "country,iso3,year,population,tb_cases_new,tb_cases_relapse,who_region"
$DataLines = @($Header)

# Helper for random values
$Rnd = New-Object System.Random

# Define some country profiles (Real-world based stats)
$Countries = @(
    @{Name="Nigeria"; ISO="NGA"; Region="AFR"; BasePop=200000000; Rate=219},
    @{Name="South Africa"; ISO="ZAF"; Region="AFR"; BasePop=59000000; Rate=554},
    @{Name="Kenya"; ISO="KEN"; Region="AFR"; BasePop=53000000; Rate=259},
    @{Name="Ethiopia"; ISO="ETH"; Region="AFR"; BasePop=115000000; Rate=132},
    @{Name="India"; ISO="IND"; Region="SEAR"; BasePop=1380000000; Rate=188},
    @{Name="Indonesia"; ISO="IDN"; Region="SEAR"; BasePop=273000000; Rate=305},
    @{Name="China"; ISO="CHN"; Region="WPR"; BasePop=1410000000; Rate=59},
    @{Name="Brazil"; ISO="BRA"; Region="AMR"; BasePop=212000000; Rate=45},
    @{Name="United States"; ISO="USA"; Region="AMR"; BasePop=331000000; Rate=2},
    @{Name="Germany"; ISO="DEU"; Region="EUR"; BasePop=83000000; Rate=5}
)

# Generate data for 2010-2022
For ($y = 2010; $y -le 2022; $y++) {
    Foreach ($c in $Countries) {
        # Population growth ~1-2%
        $Pop = [math]::Round($c.BasePop * [math]::Pow(1.015, ($y - 2020)))
        
        # Incidence variation
        $BaseRate = $c.Rate
        $YearFactor = 1.0 - (($y - 2010) * 0.02) # Slight decline trend
        If ($YearFactor -lt 0.5) {$YearFactor = 0.5}
        
        $ActualRate = $BaseRate * $YearFactor * ($Rnd.Next(90, 110) / 100)
        $TotalCases = [math]::Round(($ActualRate / 100000) * $Pop)
        
        # Split into New vs Relapse (approx 90/10 split)
        $NewCases = [math]::Round($TotalCases * 0.9)
        $RelapseCases = $TotalCases - $NewCases
        
        $Line = "{0},{1},{2},{3},{4},{5},{6}" -f $c.Name, $c.ISO, $y, $Pop, $NewCases, $RelapseCases, $c.Region
        $DataLines += $Line
    }
}

$DataLines | Out-File -FilePath $CsvPath -Encoding ASCII
Write-Host "Data generated at $CsvPath"

# 3. Calculate Ground Truth (for reference/debugging, saved to hidden location)
$ExpectedCount = 0
Foreach ($row in $DataLines[1..($DataLines.Count-1)]) {
    $cols = $row.Split(",")
    $yr = [int]$cols[2]
    $reg = $cols[6]
    If ($reg -eq "AFR" -and $yr -ge 2015 -and $yr -le 2020) {
        $ExpectedCount++
    }
}
$ExpectedCount | Out-File -FilePath "C:\Users\Docker\Documents\TBData\expected_count.txt" -Encoding ASCII

# 4. Setup Epi Info 7
# Check if running
$EpiProcess = Get-Process -Name "Analysis" -ErrorAction SilentlyContinue
If (-not $EpiProcess) {
    Write-Host "Starting Epi Info 7 Classic Analysis..."
    # Assuming standard install path for Epi Info 7
    $EpiPath = "C:\Epi_Info_7\Analysis.exe" 
    If (Test-Path $EpiPath) {
        Start-Process -FilePath $EpiPath
        Start-Sleep -Seconds 10
    } Else {
        Write-Host "WARNING: Epi Info Analysis executable not found at standard path."
    }
}

# Attempt to focus window
Add-Type -TypeDefinition @"
  using System;
  using System.Runtime.InteropServices;
  public class Win32 {
     [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
     [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  }
"@
$Proc = Get-Process -Name "Analysis" -ErrorAction SilentlyContinue | Select-Object -First 1
If ($Proc) {
    [Win32]::ShowWindow($Proc.MainWindowHandle, 3) # 3 = SW_MAXIMIZE
    [Win32]::SetForegroundWindow($Proc.MainWindowHandle)
}
PS1EOF

# Execute the PowerShell script using bash to call powershell.exe
# We use cygpath to convert /tmp path if needed, or relative path
echo "Executing Windows setup script..."
powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w /tmp/setup_logic.ps1)"

# Take initial screenshot
echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="