#!/bin/bash
# Export script for Social Impact Modeling task

source /workspace/scripts/task_utils.sh

if ! type take_screenshot &>/dev/null; then
    take_screenshot() { DISPLAY=:1 scrot "${1:-/tmp/screenshot.png}" 2>/dev/null || true; }
fi
if ! type close_openlca &>/dev/null; then
    close_openlca() { pkill -f "openLCA\|openlca" 2>/dev/null || true; sleep 3; }
fi

echo "=== Exporting Social Impact Config Result ==="

# 1. Capture Final Screenshot
take_screenshot /tmp/task_end_screenshot.png

# 2. Basic Metadata
TASK_START=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
RESULTS_DIR="/home/ga/LCA_Results"
EXPECTED_FILE="$RESULTS_DIR/transport_social_risk.zip"

# 3. Locate the Output File (Allowing for flexible location/naming)
FOUND_FILE=""
FOUND_FILE_SIZE=0
FILE_CREATED_DURING_TASK="false"

# Prioritize exact match
if [ -f "$EXPECTED_FILE" ]; then
    FOUND_FILE="$EXPECTED_FILE"
else
    # Search common locations
    FOUND_FILE=$(find "$RESULTS_DIR" "/home/ga/Desktop" "/home/ga" -maxdepth 2 -name "*social*.zip" -o -name "*transport*.zip" 2>/dev/null | head -1)
fi

if [ -n "$FOUND_FILE" ] && [ -f "$FOUND_FILE" ]; then
    FOUND_FILE_SIZE=$(stat -c %s "$FOUND_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$FOUND_FILE" 2>/dev/null || echo "0")
    
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_CREATED_DURING_TASK="true"
    fi
    
    # Ensure verifier can access it (copy to tmp)
    cp "$FOUND_FILE" /tmp/exported_package.zip
    chmod 666 /tmp/exported_package.zip
fi

# 4. Check application state
OPENLCA_RUNNING="false"
if pgrep -f "openLCA\|openlca" >/dev/null; then
    OPENLCA_RUNNING="true"
fi

# 5. Generate Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_timestamp": $TASK_START,
    "file_found": $([ -n "$FOUND_FILE" ] && echo "true" || echo "false"),
    "file_path": "$FOUND_FILE",
    "file_size": $FOUND_FILE_SIZE,
    "created_during_task": $FILE_CREATED_DURING_TASK,
    "openlca_running": $OPENLCA_RUNNING,
    "screenshot_path": "/tmp/task_end_screenshot.png"
}
EOF

# Move JSON to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export Complete ==="
echo "Result JSON written to /tmp/task_result.json"