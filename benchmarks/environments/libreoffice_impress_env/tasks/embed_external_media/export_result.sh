#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Embed External Media Result ==="

PRES_FILE="/home/ga/Documents/Presentations/company_overview.odp"

# 1. Capture Final State
take_screenshot /tmp/task_final.png ga

# 2. Record Task Stats
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 3. Check File Status
FILE_EXISTS="false"
FILE_SIZE="0"
FILE_MTIME="0"
FILE_MODIFIED="false"

if [ -f "$PRES_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c %s "$PRES_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$PRES_FILE" 2>/dev/null || echo "0")
    
    # Check if modified since start
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Attempt to verify internal structure (Basic check in bash, detailed in python)
# Just listing zip content to see if Pictures/ or Media/ exists
HAS_INTERNAL_MEDIA="false"
if [ "$FILE_EXISTS" = "true" ]; then
    if unzip -l "$PRES_FILE" | grep -qE "Pictures/|Media/"; then
        HAS_INTERNAL_MEDIA="true"
    fi
fi

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "file_exists": $FILE_EXISTS,
    "file_path": "$PRES_FILE",
    "file_size": $FILE_SIZE,
    "file_modified": $FILE_MODIFIED,
    "has_internal_media": $HAS_INTERNAL_MEDIA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move JSON to standardized location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

# 6. Close Application
echo "Closing LibreOffice..."
# Try graceful save/close first just in case, though agent should have saved
safe_xdotool ga :1 key ctrl+q || true
sleep 2
pkill -f soffice || true

echo "=== Export Complete ==="