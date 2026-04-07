#!/bin/bash
echo "=== Exporting polyline_path_measure task result ==="

source /workspace/scripts/task_utils.sh

# Capture final UI state
take_screenshot /tmp/task_final.png

# Export the collected metrics safely using Python
python3 << 'PYEOF'
import json
import os

result = {}

# 1. Capture Task Start Time
try:
    with open('/tmp/task_start_time.txt', 'r') as f:
        result['task_start'] = int(f.read().strip())
except Exception:
    result['task_start'] = 0

# 2. File paths to check
report_path = '/home/ga/DICOM/exports/polyline_report.txt'
screenshot_path = '/home/ga/DICOM/exports/polyline_screenshot.png'

result['report_exists'] = os.path.exists(report_path)
result['screenshot_exists'] = os.path.exists(screenshot_path)

result['report_content'] = ""
result['report_mtime'] = 0
result['screenshot_size'] = 0
result['screenshot_mtime'] = 0

# 3. Harvest Report Data
if result['report_exists']:
    try:
        with open(report_path, 'r', encoding='utf-8', errors='ignore') as f:
            result['report_content'] = f.read(2048)  # Read up to 2KB
        result['report_mtime'] = os.path.getmtime(report_path)
    except Exception as e:
        result['report_error'] = str(e)

# 4. Harvest Screenshot Metrics
if result['screenshot_exists']:
    try:
        result['screenshot_size'] = os.path.getsize(screenshot_path)
        result['screenshot_mtime'] = os.path.getmtime(screenshot_path)
    except:
        pass

# 5. Write to JSON securely
with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
PYEOF

# Ensure readability by the verifier
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="