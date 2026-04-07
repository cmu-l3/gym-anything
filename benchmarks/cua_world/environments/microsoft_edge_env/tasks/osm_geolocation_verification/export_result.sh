#!/bin/bash
# export_result.sh - Post-task hook for osm_geolocation_verification
# Captures the report and inspects Edge preferences for permissions.

echo "=== Exporting OSM Geolocation Verification Results ==="

# 1. Capture final screenshot (before killing Edge)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to ensure Preferences file is flushed and unlocked
echo "Stopping Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Read Task Metadata
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
REPORT_FILE="/home/ga/Desktop/geo_verification_report.txt"

# 4. Analyze the Report File
REPORT_EXISTS="false"
REPORT_CREATED_DURING_TASK="false"
REPORT_CONTENT=""

if [ -f "$REPORT_FILE" ]; then
    REPORT_EXISTS="true"
    REPORT_CONTENT=$(cat "$REPORT_FILE" | base64 -w 0) # Encode to avoid JSON breaking
    
    FILE_MTIME=$(stat -c %Y "$REPORT_FILE")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        REPORT_CREATED_DURING_TASK="true"
    fi
fi

# 5. Analyze Edge Permissions
# We look for "openstreetmap.org" in profile.content_settings.exceptions.geolocation
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"
PERMISSION_GRANTED="false"

if [ -f "$PREFS_FILE" ]; then
    PERMISSION_GRANTED=$(python3 << 'PYEOF'
import json
import sys

try:
    with open("/home/ga/.config/microsoft-edge/Default/Preferences", 'r') as f:
        data = json.load(f)
    
    geo_exceptions = data.get('profile', {}).get('content_settings', {}).get('exceptions', {}).get('geolocation', {})
    
    found = False
    for url, settings in geo_exceptions.items():
        if 'openstreetmap.org' in url:
            # setting=1 means Allow
            if settings.get('setting') == 1:
                found = True
                break
    
    print("true" if found else "false")
except Exception as e:
    print("false")
PYEOF
)
fi

# 6. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "report_exists": $REPORT_EXISTS,
    "report_created_during_task": $REPORT_CREATED_DURING_TASK,
    "report_content_base64": "$REPORT_CONTENT",
    "permission_granted": $PERMISSION_GRANTED,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete. Result saved to /tmp/task_result.json"