#!/bin/bash
# export_result.sh - Post-task hook for configure_site_permissions
# Exports Edge preferences and the agent's report for verification

set -e

echo "=== Exporting configure_site_permissions results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Take final screenshot
echo "Capturing final screenshot..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to flush Preferences to disk
# Chromium-based browsers only write the full Preferences file on exit or periodically.
# Forcing a graceful exit is best.
echo "Closing Edge to flush settings..."
pkill -u ga -f microsoft-edge || true
pkill -u ga -f msedge || true
# Wait for process to exit and file to write
sleep 3

# 3. Export Preferences
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
REPORT_FILE="/home/ga/Desktop/permission_config_report.txt"

# Check if report exists and stats
REPORT_EXISTS="false"
REPORT_MODIFIED="false"
REPORT_CONTENT=""
if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$REPORT_MTIME" -gt "$TASK_START" ]; then
        REPORT_MODIFIED="true"
    fi
    # Read report content (limit size)
    REPORT_CONTENT=$(head -c 4096 "$REPORT_FILE")
fi

# Prepare Preferences for export (need Python to parse specific sections to avoid huge JSON)
echo "Parsing Preferences..."
python3 << PYEOF
import json
import os
import sys

prefs_path = "$PREFS_FILE"
output = {
    "preferences_found": False,
    "content_settings": {}
}

if os.path.exists(prefs_path):
    output["preferences_found"] = True
    try:
        with open(prefs_path, 'r') as f:
            data = json.load(f)
        
        # Extract only the relevant content settings exceptions
        # Path: profile.content_settings.exceptions.[type]
        if 'profile' in data and 'content_settings' in data['profile'] and 'exceptions' in data['profile']['content_settings']:
            exceptions = data['profile']['content_settings']['exceptions']
            # We are interested in: notifications, media_stream_camera, geolocation
            for key in ['notifications', 'media_stream_camera', 'geolocation']:
                if key in exceptions:
                    output["content_settings"][key] = exceptions[key]
                else:
                    output["content_settings"][key] = {}
    except Exception as e:
        output["error"] = str(e)

# Write structured result to temp file
with open('/tmp/prefs_export.json', 'w') as f:
    json.dump(output, f)
PYEOF

# 4. Construct Final Result JSON
# Combine the Python output with shell variables
python3 << PYEOF
import json

# Load prefs data
try:
    with open('/tmp/prefs_export.json', 'r') as f:
        prefs_data = json.load(f)
except:
    prefs_data = {}

result = {
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "report": {
        "exists": $REPORT_EXISTS,
        "modified_after_start": $REPORT_MODIFIED,
        "content_preview": """$REPORT_CONTENT"""
    },
    "edge_state": prefs_data,
    "screenshot_path": "/tmp/task_final.png"
}

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f, indent=2)
PYEOF

# Clean up
rm -f /tmp/prefs_export.json

# Permission fix for copy_from_env
chmod 666 /tmp/task_result.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="