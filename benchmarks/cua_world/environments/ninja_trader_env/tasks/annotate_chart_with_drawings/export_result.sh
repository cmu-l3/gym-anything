# export_result.ps1 (Powershell script for Windows Environment)
$ErrorActionPreference = "Continue"
Write-Host "=== Exporting task results ==="

$resultPath = "C:\Users\Docker\Desktop\NinjaTraderTasks\annotate_chart_with_drawings_result.json"
$workspaceDir = "C:\Users\Docker\Documents\NinjaTrader 8\workspaces"
$startTimeFile = "C:\workspace\tasks\annotate_chart_with_drawings\start_time.txt"

# 1. Get Task Start Time
if (Test-Path $startTimeFile) {
    $startTime = Get-Content $startTimeFile
    $startTime = [long]$startTime
} else {
    $startTime = 0
    Write-Warning "Start time file not found"
}

# 2. Find Modified Workspace Files
# Exclude _Workspaces.xml (index file)
# Look for XML files modified AFTER start time
$files = Get-ChildItem -Path $workspaceDir -Filter "*.xml" -Recurse | 
    Where-Object { $_.Name -ne "_Workspaces.xml" -and $_.LastWriteTime.ToUnixTimeSeconds() -gt $startTime }

$workspaceModified = ($files.Count -gt 0)
$spyFound = $false
$horizontalLines = @()

# 3. Parse XML Content
# We use regex for robustness as NT8 XML serialization can be complex
foreach ($file in $files) {
    Write-Host "Processing modified file: $($file.Name)"
    try {
        $content = Get-Content $file.FullName -Raw
        
        # Check for Instrument
        if ($content -match "SPY") {
            $spyFound = $true
        }

        # Regex to find Horizontal Lines and their prices
        # Pattern looks for variations of DrawingTool serialization
        # Capture Price="..." or StartY="..." or Y="..."
        
        # Strategy: Find all "Price" attributes near "HorizontalLine"
        # Since regex in PS matches strings, we'll iterate matches
        
        # Pattern 1: Explicit HorizontalLine type with Price/Y attribute
        # Example: <DrawingTool xsi:type="HorizontalLine" ... Price="450.0" ... />
        $matches = [regex]::Matches($content, '(?i)(HorizontalLine|DrawHorizontal).*?(Price|StartY|Y)="([^"]+)"')
        
        foreach ($match in $matches) {
            $val = $match.Groups[3].Value
            # Try to parse as double
            try {
                $price = [double]$val
                $horizontalLines += $price
            } catch {
                # Ignore non-numeric matches
            }
        }

    } catch {
        Write-Warning "Failed to read $($file.Name)"
    }
}

# 4. Export JSON Result
$output = @{
    task_start = $startTime
    export_time = [DateTimeOffset]::Now.ToUnixTimeSeconds()
    workspace_modified = $workspaceModified
    spy_chart_detected = $spyFound
    detected_lines = $horizontalLines
    modified_files = @($files | Select-Object -ExpandProperty Name)
}

$json = $output | ConvertTo-Json -Depth 5
$json | Out-File $resultPath -Encoding utf8

Write-Host "Result exported to $resultPath"
Write-Host $json
Write-Host "=== Export complete ==="