#!/bin/bash
echo "=== Exporting Voyage Fuel Analysis Result ==="

# Define paths
REPORT_FILE="/home/ga/Documents/fuel_report.txt"
GT_FILE="/var/lib/bridgecommand/voyage_ground_truth.json"

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 1. Check Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    # Read first 2KB of content
    REPORT_CONTENT=$(head -c 2048 "$REPORT_FILE")
    
    # Check timestamp
    F_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$F_MTIME" -ge "$TASK_START" ]; then
        REPORT_CREATED_DURING="true"
    fi
fi

# 2. Get Ground Truth (for reference in result json, though strict verification happens in verifier)
# We need to be careful with permissions. We'll copy it to a temp file that the python script can read.
cp "$GT_FILE" /tmp/gt_temp.json

# 3. Take Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 4. Generate JSON Result
# We use Python to robustly construct the JSON
python3 << EOF
import json
import os
import re

report_exists = "$REPORT_EXISTS" == "true"
report_content = """$REPORT_CONTENT"""
report_created = "$REPORT_CREATED_DURING" == "true"

# Try to parse Total Fuel from the report content for preliminary check
extracted_fuel = -1.0
if report_exists:
    # Look for "Total: 123.45" or "123.45 Tonnes" patterns
    # Regex to find floating point number near "Total"
    match = re.search(r'TOTAL.*?(\d+\.?\d*)', report_content, re.IGNORECASE | re.DOTALL)
    if match:
        try:
            extracted_fuel = float(match.group(1))
        except:
            pass

# Load Ground Truth
try:
    with open('/tmp/gt_temp.json', 'r') as f:
        gt = json.load(f)
except:
    gt = {}

result = {
    "report_exists": report_exists,
    "report_created_during_task": report_created,
    "report_content_preview": report_content,
    "extracted_fuel_value": extracted_fuel,
    "ground_truth": gt,
    "task_start_ts": $TASK_START,
    "export_ts": $NOW
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
EOF

# Cleanup
rm -f /tmp/gt_temp.json

# Ensure permissions
chmod 644 /tmp/task_result.json
echo "Result exported to /tmp/task_result.json"