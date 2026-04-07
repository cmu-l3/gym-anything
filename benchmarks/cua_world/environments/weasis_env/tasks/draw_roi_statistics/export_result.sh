#!/bin/bash
echo "=== Exporting draw_roi_statistics result ==="

# Source utilities if available
if [ -f /workspace/scripts/task_utils.sh ]; then
    source /workspace/scripts/task_utils.sh
else
    take_screenshot() { DISPLAY=:1 scrot "$1" 2>/dev/null || true; }
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

EXPORT_DIR="/home/ga/DICOM/exports"
STATS_FILE="$EXPORT_DIR/roi_statistics.txt"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

STATS_EXISTS="false"
STATS_MTIME=0
if [ -f "$STATS_FILE" ]; then
    STATS_EXISTS="true"
    STATS_MTIME=$(stat -c %Y "$STATS_FILE" 2>/dev/null || echo "0")
fi

# Look for annotated image (png or jpg)
ANNOTATED_FILE=$(find "$EXPORT_DIR" -maxdepth 1 -type f \( -iname "roi_annotated.jpg" -o -iname "roi_annotated.jpeg" -o -iname "roi_annotated.png" \) 2>/dev/null | head -n 1)

ANNOTATED_EXISTS="false"
ANNOTATED_MTIME=0
if [ -n "$ANNOTATED_FILE" ]; then
    ANNOTATED_EXISTS="true"
    ANNOTATED_MTIME=$(stat -c %Y "$ANNOTATED_FILE" 2>/dev/null || echo "0")
fi

# Safely extract text from stats file to JSON
python3 -c '
import json, sys, os
stats_file = "/home/ga/DICOM/exports/roi_statistics.txt"
try:
    if os.path.exists(stats_file):
        with open(stats_file, "r") as f:
            content = f.read()
    else:
        content = ""
except Exception:
    content = ""
print(json.dumps(content))
' > /tmp/stats_content.json

STATS_CONTENT_JSON=$(cat /tmp/stats_content.json)

# Check if application was running
APP_RUNNING=$(pgrep -f "weasis" > /dev/null && echo "true" || echo "false")

# Build result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START,
    "stats_file_exists": $STATS_EXISTS,
    "stats_file_mtime": $STATS_MTIME,
    "annotated_file_exists": $ANNOTATED_EXISTS,
    "annotated_file_mtime": $ANNOTATED_MTIME,
    "stats_content": $STATS_CONTENT_JSON,
    "app_running": $APP_RUNNING
}
EOF

# Ensure safe movement and permissions
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/stats_content.json

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="