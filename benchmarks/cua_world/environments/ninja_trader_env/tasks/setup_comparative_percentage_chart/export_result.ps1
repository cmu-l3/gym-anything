# Note: This is a Windows environment, using PowerShell (export_result.ps1)

Write-Host "=== Exporting Comparative Percentage Chart Result ==="

$taskStartTime = 0
if (Test-Path "C:\tmp\task_start_time.txt") {
    $taskStartTime = Get-Content "C:\tmp\task_start_time.txt"
}

# 1. Capture Screenshot
# Using a python one-liner to grab screenshot since native tools might be sparse
python -c "import pyautogui; pyautogui.screenshot('C:\\tmp\\task_final.png')"

# 2. Analyze Workspace XML files
# NinjaTrader saves workspaces in My Documents
$workspaceDir = "C:\Users\Docker\Documents\NinjaTrader 8\workspaces"
$latestFile = Get-ChildItem $workspaceDir -Filter "*.xml" | 
    Where-Object { $_.Name -ne "_Workspaces.xml" } | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object -First 1

$result = @{
    task_start_time = $taskStartTime
    workspace_found = $false
    workspace_modified = $false
    instruments_found = @()
    percentage_axis_found = $false
    overlay_mode_correct = $false
    date_range_correct = $false
    chart_series_count = 0
}

if ($latestFile) {
    $result.workspace_found = $true
    
    # Check modification time against task start
    $modTime = [int][double]::Parse((Get-Date $latestFile.LastWriteTime -UFormat %s))
    if ($modTime -gt $taskStartTime) {
        $result.workspace_modified = $true
    }

    # Parse XML Content
    [xml]$xml = Get-Content $latestFile.FullName

    # Search for ChartBars (Series)
    # The structure is deeply nested. We look for 'ChartBars' elements.
    # Note: Structure varies by version, but typically Object -> ChartBars
    
    # Using specific keyword search in XML string if strict parsing is brittle
    $content = Get-Content $latestFile.FullName -Raw

    # Check Instruments
    if ($content -match "SPY") { $result.instruments_found += "SPY" }
    if ($content -match "AAPL") { $result.instruments_found += "AAPL" }
    if ($content -match "MSFT") { $result.instruments_found += "MSFT" }

    # Check Percentage Axis
    # Look for ScaleType set to Percent (Enum or String)
    # Often stored as <ScaleType>Percent</ScaleType> or <ScaleJustification>Percent</ScaleJustification>
    if ($content -match "<ScaleType>Percent</ScaleType>" -or $content -match "ScaleType=""Percent""") {
        $result.percentage_axis_found = $true
    }

    # Check Overlay (Panel Index)
    # If they are on the same panel, they usually share <Panel>0</Panel> or similar.
    # We count distinct Panel IDs associated with ChartBars.
    # This is hard to regex, assuming XML parsing:
    $panels = Select-Xml -Xml $xml -XPath "//Panel" | ForEach-Object { $_.Node.InnerText }
    $uniquePanels = $panels | Select-Object -Unique
    
    # Heuristic: If we have 3 instruments but mostly Panel 0 (or 1 unique panel), it's overlaid.
    # If we have Panel 0, Panel 1, Panel 2, it's separate.
    $panelCount = ($uniquePanels | Measure-Object).Count
    if ($panelCount -eq 1) {
        $result.overlay_mode_correct = $true
    }

    # Date Range Check
    if ($content -match "2023-01-01" -and $content -match "2023-12-31") {
        $result.date_range_correct = $true
    }
}

# 3. Export to JSON
$json = $result | ConvertTo-Json -Depth 5
$json | Out-File -FilePath "C:\tmp\task_result.json" -Encoding ascii

Write-Host "Result exported to C:\tmp\task_result.json"