#!/bin/bash
echo "=== Exporting develop_and_backtest_ema_strategy results ==="

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Create PowerShell export script to gather Windows-side evidence
cat > /tmp/export_nt8.ps1 << 'PSEOF'
$Result = @{
    "strategy_exists" = $false
    "file_created_after_start" = $false
    "source_code" = ""
    "compilation_success" = $false
    "backtest_configured" = $false
    "workspace_saved" = $false
}

$StrategyPath = "C:\Users\Docker\Documents\NinjaTrader 8\bin\Custom\Strategies\SampleEMACrossover.cs"
$WorkspacesPath = "C:\Users\Docker\Documents\NinjaTrader 8\workspaces"

# Check Strategy File
if (Test-Path $StrategyPath) {
    $Result["strategy_exists"] = $true
    
    # Check timestamp
    $Item = Get-Item $StrategyPath
    $CreationTime = $Item.CreationTime.ToString("yyyy-MM-dd HH:mm:ss")
    $LastWriteTime = $Item.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $Result["file_timestamps"] = @{ "created" = $CreationTime; "modified" = $LastWriteTime }
    
    # Read Source Code
    $Result["source_code"] = Get-Content $StrategyPath -Raw
}

# Check Workspace for Backtest Configuration
# We look for XML files containing "SampleEMACrossover" and "StrategyAnalyzer"
$WorkspaceFiles = Get-ChildItem $WorkspacesPath -Filter "*.xml"
foreach ($File in $WorkspaceFiles) {
    if ($File.Name -ne "_Workspaces.xml") {
        $Content = Get-Content $File.FullName -Raw
        if ($Content -match "SampleEMACrossover" -and $Content -match "StrategyAnalyzer") {
            $Result["backtest_configured"] = $true
        }
        
        # Check if workspace was saved recently
        # Note: This is a loose check, relying on file modification
        $Result["workspace_saved"] = $true # Assuming existence implies save for now, verifier checks timestamps
    }
}

# Output to JSON
$Result | ConvertTo-Json -Depth 5 | Out-File "C:\Users\Docker\Desktop\task_export.json" -Encoding utf8
PSEOF

# Run extraction
powershell.exe -ExecutionPolicy Bypass -File "/tmp/export_nt8.ps1"

# Move the JSON from Windows path to Linux path (if they differ in the env, usually mapped)
# Assuming C:\Users\Docker\Desktop is mapped or accessible. 
# In this env, /workspace is mapped. Let's try to copy from the Windows path if possible.
# Using 'cat' via bash on the generated file:

if [ -f "/c/Users/Docker/Desktop/task_export.json" ]; then
    cp "/c/Users/Docker/Desktop/task_export.json" /tmp/temp_result.json
elif [ -f "/mnt/c/Users/Docker/Desktop/task_export.json" ]; then
    cp "/mnt/c/Users/Docker/Desktop/task_export.json" /tmp/temp_result.json
else
    # Fallback: try to read it via powershell to stdout
    powershell.exe -Command "Get-Content 'C:\Users\Docker\Desktop\task_export.json'" > /tmp/temp_result.json
fi

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Format final JSON for the verifier
# We embed the PowerShell result into our standard format
cat > /tmp/task_result.json << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "screenshot_path": "/tmp/task_final.png",
    "windows_data": $(cat /tmp/temp_result.json 2>/dev/null || echo "{}")
}
EOF

# Cleanup
rm -f /tmp/setup_nt8.ps1 /tmp/export_nt8.ps1 /tmp/temp_result.json

echo "Result exported to /tmp/task_result.json"