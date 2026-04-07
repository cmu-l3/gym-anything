#!/bin/bash
# export_result.sh - Post-task hook for configure_secure_dns_doh
# Extracts Edge settings and verification files.

echo "=== Exporting task results ==="

TASK_START=$(cat /tmp/task_start_ts.txt 2>/dev/null || echo "0")
RESULT_JSON="/tmp/task_result.json"

# 1. Take final screenshot of the desktop/browser state
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure Preferences are flushed to disk
echo "Closing Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Analyze state using Python
python3 << PYEOF
import json
import os
import sys

task_start = int("${TASK_START}")
prefs_path = "/home/ga/.config/microsoft-edge/Default/Preferences"
screenshot_path = "/home/ga/Desktop/doh_verification.png"
status_file_path = "/home/ga/Desktop/doh_status.txt"

result = {
    "doh_mode": "unknown",
    "doh_templates": "",
    "screenshot_exists": False,
    "screenshot_valid_time": False,
    "status_file_exists": False,
    "status_file_content": "",
    "status_file_valid_time": False
}

# Check Preferences
if os.path.exists(prefs_path):
    try:
        with open(prefs_path, 'r') as f:
            prefs = json.load(f)
            doh = prefs.get('dns_over_https', {})
            result['doh_mode'] = doh.get('mode', 'unknown')
            result['doh_templates'] = doh.get('templates', '')
    except Exception as e:
        print(f"Error reading preferences: {e}", file=sys.stderr)

# Check Screenshot
if os.path.exists(screenshot_path):
    result['screenshot_exists'] = True
    mtime = os.path.getmtime(screenshot_path)
    if mtime > task_start:
        result['screenshot_valid_time'] = True

# Check Status Text File
if os.path.exists(status_file_path):
    result['status_file_exists'] = True
    mtime = os.path.getmtime(status_file_path)
    if mtime > task_start:
        result['status_file_valid_time'] = True
    try:
        with open(status_file_path, 'r') as f:
            result['status_file_content'] = f.read().strip()
    except:
        pass

# Write result to JSON
with open("${RESULT_JSON}", 'w') as f:
    json.dump(result, f, indent=2)

print("Export analysis complete.")
PYEOF

# 4. Set permissions for the result file so verification script can read it
chmod 666 "${RESULT_JSON}" 2>/dev/null || true

cat "${RESULT_JSON}"
echo "=== Export complete ==="