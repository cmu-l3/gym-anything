#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
PORTFOLIO_FILE="/home/ga/.jstock/1.0.7/UnitedState/portfolios/My Portfolio/buyportfolio.csv"

# Take final screenshot
echo "Capturing final state..."
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_final.png 2>/dev/null || \
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority import -window root /tmp/task_final.png 2>/dev/null || true

# Use Python to parse the CSV and create a structured JSON result
# This avoids fragile bash CSV parsing and ensures proper handling of quoted fields
python3 -c "
import csv
import json
import os
import sys

csv_path = '$PORTFOLIO_FILE'
result = {
    'task_start': $TASK_START,
    'task_end': $TASK_END,
    'file_exists': False,
    'file_mtime': 0,
    'data': [],
    'app_running': False
}

# Check file existence and timestamp
if os.path.exists(csv_path):
    result['file_exists'] = True
    result['file_mtime'] = int(os.path.getmtime(csv_path))
    
    try:
        # Read CSV data
        with open(csv_path, 'r', encoding='utf-8') as f:
            reader = csv.DictReader(f)
            # Normalize headers (remove BOM if present, strip spaces)
            reader.fieldnames = [name.strip() for name in reader.fieldnames]
            for row in reader:
                # Clean up row data
                clean_row = {k: v.strip() if v else '' for k, v in row.items()}
                result['data'].append(clean_row)
    except Exception as e:
        result['error'] = str(e)

# Check if app is running
if os.system('pgrep -f jstock.jar > /dev/null') == 0:
    result['app_running'] = True

# Write result to temp file
with open('/tmp/temp_result.json', 'w') as f:
    json.dump(result, f, indent=2)
"

# Move result with permissions check
rm -f /tmp/task_result.json 2>/dev/null || true
cp /tmp/temp_result.json /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="