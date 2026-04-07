#!/bin/bash
echo "=== Setting up Filter Waypoints Task ==="

# We use a PowerShell script invoked from Bash to ensure deep Windows compatibility 
# for UI manipulation and file pathing in the BaseCamp environment.
cat << 'EOF' > C:\setup_task.ps1
$ErrorActionPreference = 'Stop'

# 1. Record task start time for anti-gaming verification
[int][double]::Parse((Get-Date (Get-Date).ToUniversalTime() -UFormat %s)) | Out-File -FilePath 'C:\task_start_time.txt' -Encoding ascii

# 2. Setup Data Directory
$dataDir = "C:\workspace\data"
if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir }

# 3. Create raw GPX dataset with varying elevations
$gpxContent = @"
<?xml version="1.0" encoding="UTF-8" standalone="no" ?>
<gpx xmlns="http://www.topografix.com/GPX/1/1" version="1.1" creator="SetupScript">
  <metadata><name>Amphibian Sightings</name></metadata>
  <wpt lat="42.431" lon="-71.101"><ele>36.5</ele><name>Sighting_01</name><desc>120 ft</desc></wpt>
  <wpt lat="42.432" lon="-71.102"><ele>54.8</ele><name>Sighting_02</name><desc>180 ft</desc></wpt>
  <wpt lat="42.433" lon="-71.103"><ele>65.5</ele><name>Sighting_03</name><desc>215 ft</desc></wpt>
  <wpt lat="42.434" lon="-71.104"><ele>76.2</ele><name>Sighting_04</name><desc>250 ft</desc></wpt>
  <wpt lat="42.435" lon="-71.105"><ele>88.3</ele><name>Sighting_05</name><desc>290 ft</desc></wpt>
  <wpt lat="42.436" lon="-71.106"><ele>103.6</ele><name>Sighting_06</name><desc>340 ft</desc></wpt>
  <wpt lat="42.437" lon="-71.107"><ele>118.8</ele><name>Sighting_07</name><desc>390 ft</desc></wpt>
  <wpt lat="42.438" lon="-71.108"><ele>125.0</ele><name>Sighting_08</name><desc>410 ft</desc></wpt>
  <wpt lat="42.439" lon="-71.109"><ele>137.1</ele><name>Sighting_09</name><desc>450 ft</desc></wpt>
  <wpt lat="42.440" lon="-71.110"><ele>167.6</ele><name>Sighting_10</name><desc>550 ft</desc></wpt>
</gpx>
"@
$gpxContent | Out-File -FilePath "$dataDir\amphibian_sightings.gpx" -Encoding utf8

# 4. Clean up previous artifacts
$outDir = "C:\workspace\output"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force -Path $outDir }
if (Test-Path "$outDir\mid_elevation_sightings.gpx") { Remove-Item "$outDir\mid_elevation_sightings.gpx" -Force }

# 5. Launch Garmin BaseCamp
$bcPath = "C:\Program Files (x86)\Garmin\BaseCamp\BaseCamp.exe"
if (-not (Test-Path $bcPath)) { $bcPath = "C:\Program Files\Garmin\BaseCamp\BaseCamp.exe" }

if (Test-Path $bcPath) {
    Start-Process $bcPath
    Start-Sleep -Seconds 12  # Wait for BaseCamp to initialize

    # Inject C# to manipulate Window to force maximize and focus
    Add-Type -TypeDefinition "
        using System;
        using System.Runtime.InteropServices;
        public class Win32 {
            [DllImport(`"user32.dll`")]
            public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
            [DllImport(`"user32.dll`")]
            public static extern bool SetForegroundWindow(IntPtr hWnd);
        }
    "
    $bcProcess = Get-Process -Name "BaseCamp" -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($bcProcess) {
        [Win32]::ShowWindow($bcProcess.MainWindowHandle, 3) # 3 = MAXIMIZE
        [Win32]::SetForegroundWindow($bcProcess.MainWindowHandle)
    }
} else {
    Write-Warning "Garmin BaseCamp executable not found!"
}
EOF

powershell.exe -ExecutionPolicy Bypass -File C:\setup_task.ps1
echo "=== Task setup complete ==="