#!/bin/bash
echo "=== Exporting Task Results ==="

# Define paths
OUTPUT_FILE_WIN="C:\Users\Docker\Documents\TBData\output\afr_tb_2015_2020.csv"
OUTPUT_FILE_UNIX="/home/docker/Documents/TBData/output/afr_tb_2015_2020.csv" 
# Note: In dockur/windows or similar envs, path mapping might vary. 
# We'll use PowerShell to copy the file to a known transfer location /tmp if needed,
# or access it directly if mounted. 
# Assuming standard agent user 'ga' or 'Docker' has access via mapped drive or we use PS to cat it.

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Extract Result Data using PowerShell
# We output a JSON object directly from PowerShell to parsing
cat << 'PS1EOF' > /tmp/export_logic.ps1
$OutputPath = "C:\Users\Docker\Documents\TBData\output\afr_tb_2015_2020.csv"
$ExpectedCountPath = "C:\Users\Docker\Documents\TBData\expected_count.txt"

$Exists = Test-Path $OutputPath
$Size = 0
$Content = ""
$ModifiedTime = 0

If ($Exists) {
    $Item = Get-Item $OutputPath
    $Size = $Item.Length
    $ModifiedTime = [int][double]::Parse((Get-Date -Date $Item.LastWriteTime -UFormat %s))
    $Content = Get-Content $OutputPath -Raw
}

$ExpectedCount = 0
If (Test-Path $ExpectedCountPath) {
    $ExpectedCount = [int](Get-Content $ExpectedCountPath)
}

$Result = @{
    file_exists = $Exists
    file_size = $Size
    modified_time = $ModifiedTime
    expected_count = $ExpectedCount
    # Embed content as Base64 to avoid CSV parsing issues in transit
    content_b64 = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($Content))
}

$Result | ConvertTo-Json -Compress
PS1EOF

# Run export script and save output
powershell.exe -ExecutionPolicy Bypass -File "$(cygpath -w /tmp/export_logic.ps1)" > /tmp/ps_output.json

# 3. Create Final JSON for Verifier
# We merge the PS output with task timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Helper python to merge and format
python3 -c "
import json
import base64
import os
import time

try:
    with open('/tmp/ps_output.json', 'r') as f:
        ps_data = json.load(f)
except:
    ps_data = {'file_exists': False, 'content_b64': ''}

task_start = int($TASK_START)
task_end = int($TASK_END)

# Check if file created during task
file_mtime = ps_data.get('modified_time', 0)
created_during = (file_mtime >= task_start)

# Decode content
content = ''
if ps_data.get('content_b64'):
    try:
        content = base64.b64decode(ps_data['content_b64']).decode('utf-8')
    except:
        pass

final_result = {
    'task_start': task_start,
    'task_end': task_end,
    'output_exists': ps_data.get('file_exists', False),
    'file_created_during_task': created_during,
    'output_size_bytes': ps_data.get('file_size', 0),
    'ground_truth_count': ps_data.get('expected_count', 0),
    'csv_content': content,
    'screenshot_path': '/tmp/task_final.png'
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(final_result, f)
"

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export Complete ==="