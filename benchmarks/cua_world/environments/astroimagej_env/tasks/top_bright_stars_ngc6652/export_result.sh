#!/bin/bash
set -e
echo "=== Exporting Top Bright Stars task results ==="

source /workspace/scripts/task_utils.sh

# Take final screenshot
take_screenshot /tmp/task_final.png

# Capture active windows
WINDOWS_LIST=$(DISPLAY=:1 wmctrl -l 2>/dev/null || echo "")

AIJ_RUNNING="false"
if pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null; then
    AIJ_RUNNING="true"
fi

# Check for the expected output catalog file
CATALOG_PATH="/home/ga/AstroImages/ngc6652_project/bright_star_catalog.txt"
CATALOG_EXISTS="false"
CATALOG_CONTENT=""
CREATED_DURING_TASK="false"
CATALOG_SIZE=0

if [ -f "$CATALOG_PATH" ]; then
    CATALOG_EXISTS="true"
    CATALOG_SIZE=$(stat -c %s "$CATALOG_PATH" 2>/dev/null || echo "0")
    CATALOG_MTIME=$(stat -c %Y "$CATALOG_PATH" 2>/dev/null || echo "0")
    TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
    
    if [ "$CATALOG_MTIME" -ge "$TASK_START" ]; then
        CREATED_DURING_TASK="true"
    fi
    
    # Read up to 50 lines of the catalog for the verifier
    CATALOG_CONTENT=$(head -n 50 "$CATALOG_PATH" | tr '\n' '|' | tr '"' "'")
fi

# Search for any alternative results files if main is not found
ALT_RESULTS_CONTENT=""
if [ "$CATALOG_EXISTS" = "false" ]; then
    ALT_FILE=$(find /home/ga -maxdepth 4 -type f \( -name "*catalog*" -o -name "*bright*" -o -name "*.txt" \) -newer /tmp/task_start_time.txt 2>/dev/null | grep -i "ngc6652" | head -1)
    if [ -n "$ALT_FILE" ]; then
        CATALOG_EXISTS="true"
        CATALOG_PATH="$ALT_FILE"
        CATALOG_SIZE=$(stat -c %s "$CATALOG_PATH" 2>/dev/null || echo "0")
        CREATED_DURING_TASK="true"
        CATALOG_CONTENT=$(head -n 50 "$CATALOG_PATH" | tr '\n' '|' | tr '"' "'")
        ALT_RESULTS_CONTENT="Found alternative file: $ALT_FILE"
    fi
fi

# Build JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "aij_running": $AIJ_RUNNING,
    "catalog_exists": $CATALOG_EXISTS,
    "catalog_created_during_task": $CREATED_DURING_TASK,
    "catalog_size_bytes": $CATALOG_SIZE,
    "catalog_content": "$CATALOG_CONTENT",
    "alternative_info": "$ALT_RESULTS_CONTENT",
    "windows_list": "$(echo "$WINDOWS_LIST" | tr '\n' '|' | tr '"' "'")"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result JSON generated:"
cat /tmp/task_result.json
echo "=== Export Complete ==="