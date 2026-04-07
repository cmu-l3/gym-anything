#!/bin/bash
echo "=== Exporting task results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Use PowerShell to safely check files and extract metadata in Windows
cat << 'EOF' > /tmp/export_helper.ps1
param([int]$StartTime)

$report_path = "C:\workspace\output\distance_report.txt"
$gpx_path = "C:\workspace\output\resupply_plan.gpx"

$report_exists = $false
$report_created_during = $false
$gpx_exists = $false
$gpx_created_during = $false

if (Test-Path $report_path) {
    $report_exists = $true
    $mtime = (Get-Item $report_path).LastWriteTime.ToUniversalTime()
    $unix_mtime = [int][double]::Parse((Get-Date $mtime -UFormat %s))
    if ($unix_mtime -ge $StartTime) { $report_created_during = $true }
    
    # Copy for Linux-side verifier
    Copy-Item $report_path "C:\workspace\output\distance_report_copy.txt" -ErrorAction SilentlyContinue
}

if (Test-Path $gpx_path) {
    $gpx_exists = $true
    $mtime = (Get-Item $gpx_path).LastWriteTime.ToUniversalTime()
    $unix_mtime = [int][double]::Parse((Get-Date $mtime -UFormat %s))
    if ($unix_mtime -ge $StartTime) { $gpx_created_during = $true }
    
    # Copy for Linux-side verifier
    Copy-Item $gpx_path "C:\workspace\output\resupply_plan_copy.gpx" -ErrorAction SilentlyContinue
}

$result = @{
    task_start = $StartTime
    report_exists = $report_exists
    report_created_during_task = $report_created_during
    gpx_exists = $gpx_exists
    gpx_created_during_task = $gpx_created_during
}

$json = $result | ConvertTo-Json
Set-Content -Path "C:\workspace\output\task_result.json" -Value $json -Encoding Ascii
EOF

powershell.exe -ExecutionPolicy Bypass -File /tmp/export_helper.ps1 -StartTime $TASK_START

# Move to standard /tmp/ locations for the verifier
cp /c/workspace/output/task_result.json /tmp/task_result.json 2>/dev/null || true
cp /c/workspace/output/distance_report_copy.txt /tmp/distance_report.txt 2>/dev/null || true
cp /c/workspace/output/resupply_plan_copy.gpx /tmp/resupply_plan.gpx 2>/dev/null || true

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

echo "Result JSON saved to /tmp/task_result.json"
cat /tmp/task_result.json 2>/dev/null || true
echo "=== Export complete ==="