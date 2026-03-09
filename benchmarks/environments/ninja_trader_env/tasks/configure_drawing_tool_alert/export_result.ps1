# <file name="export_result.ps1">
Write-Host "=== Exporting Drawing Tool Alert Result ==="

$resultPath = "C:\Users\Docker\Desktop\NinjaTraderTasks\configure_drawing_tool_alert_result.json"
$workspaceDir = "C:\Users\Docker\Documents\NinjaTrader 8\workspaces"
$startTimeStr = Get-Content "C:\tmp\task_start_time.txt" -ErrorAction SilentlyContinue
$startTime = [DateTime]::Parse($startTimeStr)

$result = @{
    workspace_modified = $false
    instrument_found = $false
    tool_found = $false
    price_correct = $false
    alert_enabled = $false
    condition_correct = $false
    price_value = 0.0
    found_condition = "None"
    timestamp = (Get-Date).ToString("o")
}

# Check for modified workspace files
$files = Get-ChildItem -Path $workspaceDir -Filter "*.xml" | Where-Object { $_.Name -ne "_Workspaces.xml" }

foreach ($file in $files) {
    if ($file.LastWriteTime -gt $startTime) {
        $result.workspace_modified = $true
        Write-Host "Analyzing modified workspace: $($file.Name)"
        
        # Read content (simple text parsing since XML schema is complex)
        $content = Get-Content $file.FullName -Raw
        
        # 1. Check Instrument (SPY)
        if ($content -match "SPY") {
            $result.instrument_found = $true
        }
        
        # 2. Check Horizontal Line existence
        if ($content -match "HorizontalLine") {
            $result.tool_found = $true
            
            # 3. Check Price Level (500)
            # Regex to find Y value: <Y>500</Y> or <Y>500.0</Y>
            # NinjaTrader serializes doubles, might look like <Y xmlns:xsd...>500</Y> or just <Y>500</Y>
            # We look for the value 500 near the HorizontalLine context
            # A broader regex to capture the value
            if ($content -match "<Y[^>]*>(499\.\d+|500(\.0+)?)</Y>") {
                $result.price_correct = $true
                $result.price_value = 500.0
            }
            
            # 4. Check Alert Enabled
            # Context: <Alert>...<IsEnabled>true</IsEnabled>...</Alert>
            # This is tricky with regex on the whole file. 
            # We look for the Alert block specifically.
            
            # Simple check: Does "IsEnabled>true" appear? (Weak check)
            # Better: Check if it appears near HorizontalLine. 
            # Since this is a specific task, we assume if they enabled an alert, it's likely on the tool.
            if ($content -match "<Alert>.*<IsEnabled>true</IsEnabled>") {
                 # To be safer, we check if it's NOT a generic price alert but inside drawing tools?
                 # NinjaTrader XML hierarchy: ChartControl -> DrawingTools -> UIDrawingTool -> HorizontalLine -> Alert
                 if ($content -match "<DrawingTools>.*<HorizontalLine>.*<Alert>.*<IsEnabled>true</IsEnabled>") {
                     $result.alert_enabled = $true
                 }
            }
            
            # 5. Check Condition (CrossAbove)
            if ($content -match "CrossAbove" -or $content -match "CrossesAbove") {
                $result.condition_correct = $true
                $result.found_condition = "CrossAbove"
            }
        }
    }
}

# Convert to JSON and save
$json = $result | ConvertTo-Json
$json | Out-File -FilePath $resultPath -Encoding UTF8

Write-Host "Result exported to $resultPath"
Type $resultPath
# </file>