#!/bin/bash
echo "=== Exporting Task Results ==="

# Record End Time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Define Paths (inside Windows env, accessed via mounts or copy)
# In this environment, we might need to copy from the Windows user dir to /tmp for easy access
# We'll use a PowerShell script to gather file stats and content

cat << 'PS1EOF' > /tmp/export_script.ps1
$ReportPath = "C:\Users\Docker\Documents\adequacy_audit.txt"
$ImgPath = "C:\Users\Docker\Documents\peak_stress_event.png"
$ResultPath = "C:\temp\export_data.json"

# Ensure temp dir exists
if (-not (Test-Path "C:\temp")) { New-Item -ItemType Directory -Path "C:\temp" | Out-Null }

$ReportExists = Test-Path $ReportPath
$ImgExists = Test-Path $ImgPath

$ReportContent = ""
$ReportMTime = 0
$ImgMTime = 0
$ImgSize = 0

if ($ReportExists) {
    $ReportContent = Get-Content -Path $ReportPath -Raw
    $ReportMTime = (Get-Item $ReportPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
}

if ($ImgExists) {
    $ImgMTime = (Get-Item $ImgPath).LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
    $ImgSize = (Get-Item $ImgPath).Length
}

# Create JSON object
$Result = @{
    report_exists = $ReportExists
    image_exists = $ImgExists
    report_content = $ReportContent
    report_mtime = $ReportMTime
    image_mtime = $ImgMTime
    image_size_bytes = $ImgSize
}

# Convert to JSON and save
$Result | ConvertTo-Json -Depth 5 | Out-File -FilePath $ResultPath -Encoding UTF8
PS1EOF

# Run PowerShell export
powershell -ExecutionPolicy Bypass -File /tmp/export_script.ps1 > /dev/null 2>&1

# Move the JSON to a location accessible by 'copy_from_env' (e.g., /tmp/task_result.json)
# Assuming C:\temp is mapped or accessible, or we just cat it
# In a Windows container, we often need to carefully handle paths.
# Let's assume we can read the file we just created.
# We will cat it to stdout and capture it, or move it.
cat /c/temp/export_data.json > /tmp/task_result.json 2>/dev/null || \
powershell -Command "Get-Content C:\temp\export_data.json" > /tmp/task_result.json

# Inject timestamp data from Linux side
# (We do this because Windows time might drift or be formatted differently, 
# but mostly to include the task start/end verification logic)
# Actually, verifying timestamps inside python is easier if we pass the raw strings.

echo "=== Export Complete ==="