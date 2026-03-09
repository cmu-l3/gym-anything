# Again, providing PowerShell content as export_result.ps1 matching the hook.

Write-Host "=== Exporting Configure Hot Keys Result ==="

$ConfigDir = "C:\Users\Docker\Documents\NinjaTrader 8\config"
$ResultTxt = "C:\Users\Docker\Desktop\NinjaTraderTasks\configure_hot_keys_result.txt"
$StartTimeFile = "C:\tmp\task_start_time.txt"
$JsonOut = "C:\tmp\task_result.json"

# 1. Read Task Start Time
if (Test-Path $StartTimeFile) {
    $StartTime = Get-Content $StartTimeFile | Measure-Object -Maximum | Select-Object -ExpandProperty Maximum
} else {
    $StartTime = 0
}

# 2. Check Result Text File
$TextFileExists = $false
$TextContent = ""
if (Test-Path $ResultTxt) {
    $TextFileExists = $true
    $TextContent = Get-Content $ResultTxt -Raw
}

# 3. Analyze Config Files (Look for modifications and content)
$ConfigModified = $false
$ModifiedFiles = @()
$HotKeyFindings = @()

# Get XML files modified after start time
$XmlFiles = Get-ChildItem -Path $ConfigDir -Filter "*.xml"
foreach ($file in $XmlFiles) {
    $modTime = $file.LastWriteTime
    $modEpoch = [math]::Round(($modTime - (Get-Date "01/01/1970")).TotalSeconds)
    
    if ($modEpoch -gt $StartTime) {
        $ConfigModified = $true
        $ModifiedFiles += $file.Name
        
        # Search content for our keys
        $content = Get-Content $file.FullName -Raw
        
        # Simple regex checks for evidence
        if ($content -match "Ctrl") { $HotKeyFindings += "Found 'Ctrl' in $($file.Name)" }
        if ($content -match "Shift") { $HotKeyFindings += "Found 'Shift' in $($file.Name)" }
        # Check specific combinations (loose check to handle XML variations)
        # We look for the Action name and the key close to each other
        if ($content -match "Chart" -and $content -match "Key=`"C`"") { $HotKeyFindings += "Potential Chart-C binding in $($file.Name)" }
        if ($content -match "StrategyAnalyzer" -and $content -match "Key=`"A`"") { $HotKeyFindings += "Potential Strat-A binding in $($file.Name)" }
        if ($content -match "MarketAnalyzer" -and $content -match "Key=`"M`"") { $HotKeyFindings += "Potential Market-M binding in $($file.Name)" }
        
        # Grab snippet around "HotKey" tags
        $lines = Get-Content $file.FullName
        $matchLines = $lines | Select-String -Pattern "HotKey" -Context 0,2
        if ($matchLines) {
             foreach ($m in $matchLines) { $HotKeyFindings += "Raw: $($m.Line.Trim())" }
        }
    }
}

# 4. Check for Opened Windows (Functional Verification)
$OpenWindows = @()
$gps = Get-Process | Where-Object { $_.MainWindowTitle -ne "" }
foreach ($p in $gps) {
    $OpenWindows += $p.MainWindowTitle
}

$ChartOpened = ($OpenWindows -match "Chart").Count -gt 0
$StratOpened = ($OpenWindows -match "Strategy Analyzer").Count -gt 0
$MarketOpened = ($OpenWindows -match "Market Analyzer").Count -gt 0

# 5. Take Screenshot
# Using a python one-liner or similar tool available in the env if scrot isn't available on Windows
# Assuming the env has python installed as per description
python -c "import pyautogui; pyautogui.screenshot('C:\\tmp\\task_final.png')" 2>$null

# 6. Create JSON Result
$ResultObject = @{
    task_start = $StartTime
    config_modified = $ConfigModified
    modified_files = $ModifiedFiles
    hot_key_findings = $HotKeyFindings
    text_file_exists = $TextFileExists
    text_content = $TextContent
    windows_detected = @{
        chart = $ChartOpened
        strategy_analyzer = $StratOpened
        market_analyzer = $MarketOpened
        all_titles = $OpenWindows
    }
}

$ResultJson = $ResultObject | ConvertTo-Json -Depth 4
$ResultJson | Out-File -FilePath $JsonOut -Encoding ascii

Write-Host "Result exported to $JsonOut"
Get-Content $JsonOut