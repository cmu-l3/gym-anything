#!/bin/bash
# Export script for Custom Dashboard Start Page task

echo "=== Exporting task results ==="

# 1. Take final screenshot (Visual evidence)
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Kill Edge to flush preferences to disk
echo "Closing Edge to flush preferences..."
pkill -u ga -f microsoft-edge 2>/dev/null || true
pkill -u ga -f msedge 2>/dev/null || true
sleep 3

# 3. Gather Task Data
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
DASHBOARD_PATH="/home/ga/Desktop/travel_dashboard.html"
PREFS_FILE="/home/ga/.config/microsoft-edge/Default/Preferences"

# Check Dashboard File
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_CONTENT=""
FILE_CREATED_DURING_TASK="false"

if [ -f "$DASHBOARD_PATH" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$DASHBOARD_PATH")
    FILE_MTIME=$(stat -c %Y "$DASHBOARD_PATH")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Read content for verification (limit size to prevent massive JSONs)
    # Base64 encode to safely transport HTML in JSON
    FILE_CONTENT=$(head -c 5000 "$DASHBOARD_PATH" | base64 -w 0)
fi

# Check Edge Preferences for Startup Config
STARTUP_URLS="[]"
RESTORE_ON_STARTUP="5" # Default is 5 (New Tab)
HOMEPAGE=""

if [ -f "$PREFS_FILE" ]; then
    # Extract specific keys using Python
    PREFS_DATA=$(python3 << PYEOF
import json
try:
    with open("$PREFS_FILE", "r") as f:
        data = json.load(f)
    session = data.get("session", {})
    startup_urls = session.get("startup_urls", [])
    restore = session.get("restore_on_startup", 5)
    homepage = data.get("homepage", "")
    
    print(json.dumps({
        "startup_urls": startup_urls,
        "restore_on_startup": restore,
        "homepage": homepage
    }))
except:
    print(json.dumps({"startup_urls": [], "restore_on_startup": 5, "homepage": ""}))
PYEOF
    )
fi

# 4. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "file_exists": $FILE_EXISTS,
    "file_size": $FILE_SIZE,
    "file_created_during_task": $FILE_CREATED_DURING_TASK,
    "file_content_b64": "$FILE_CONTENT",
    "edge_prefs": $PREFS_DATA
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"