# import_data.ps1 - Import Yahoo Finance historical data into NinjaTrader 8.
#
# This script uses the PyAutoGUI TCP server (port 5555) to automate the
# Tools → Import → Historical Data workflow. It imports daily OHLCV data
# for SPY, AAPL, and MSFT from Desktop\NinjaTraderTasks\.
#
# Prerequisites:
#   - NinjaTrader must be running in the interactive session
#   - PyAutoGUI server must be running on port 5555
#   - Data files (*.Last.txt) must be in NinjaTraderTasks folder
#
# Data format: NinjaTrader (end of bar timestamps), semicolon-delimited
#   yyyyMMdd;open;high;low;close;volume

$ErrorActionPreference = "Continue"

# Load shared helpers
$utils = "C:\workspace\scripts\task_utils.ps1"
if (Test-Path $utils) {
    . $utils
} else {
    Write-Host "ERROR: task_utils.ps1 not found at $utils"
    exit 1
}

Write-Host "=== Importing historical data into NinjaTrader ==="

# Verify PyAutoGUI server is reachable
$pingResult = Send-PyAutoGUI -Command @{action="ping"}
if (-not $pingResult -or -not $pingResult.success) {
    Write-Host "WARNING: PyAutoGUI server not responding. Data import may fail."
}

$dataDir = "C:\Users\Docker\Desktop\NinjaTraderTasks"
$dataFiles = @("AAPL.Last.txt", "MSFT.Last.txt", "SPY.Last.txt")

foreach ($dataFile in $dataFiles) {
    $filePath = Join-Path $dataDir $dataFile
    if (-not (Test-Path $filePath)) {
        Write-Host "Skipping $dataFile - not found at $filePath"
        continue
    }

    Write-Host "Importing $dataFile ..."

    # Open Tools → Import → Historical Data
    # Click Tools menu
    PyAutoGUI-Click -X 440 -Y 130
    Start-Sleep -Seconds 1

    # Click Import submenu
    PyAutoGUI-Click -X 439 -Y 361
    Start-Sleep -Milliseconds 500

    # Click Historical Data...
    PyAutoGUI-Click -X 723 -Y 396
    Start-Sleep -Seconds 2

    # Click Import button in the Historical Data dialog
    PyAutoGUI-Click -X 789 -Y 685
    Start-Sleep -Seconds 2

    # Navigate to Desktop → NinjaTraderTasks in file browser
    # Click Desktop in left panel
    PyAutoGUI-Click -X 189 -Y 338
    Start-Sleep -Seconds 1

    # Double-click NinjaTraderTasks folder
    PyAutoGUI-Click -X 355 -Y 264
    PyAutoGUI-Click -X 355 -Y 264
    Start-Sleep -Seconds 1

    # Type the filename in the File name field
    PyAutoGUI-Click -X 405 -Y 515
    PyAutoGUI-Click -X 405 -Y 515
    PyAutoGUI-Click -X 405 -Y 515
    Start-Sleep -Milliseconds 300
    PyAutoGUI-Write -Text $dataFile
    Start-Sleep -Milliseconds 500

    # Click Open
    PyAutoGUI-Click -X 575 -Y 545
    Start-Sleep -Seconds 3

    # Click OK on the success dialog (502 data records successfully imported)
    PyAutoGUI-Click -X 621 -Y 464
    Start-Sleep -Seconds 1

    # Close the Historical Data window
    PyAutoGUI-Click -X 843 -Y 115
    Start-Sleep -Seconds 1

    Write-Host "  $dataFile imported successfully."
}

Write-Host "=== Data import complete ==="
