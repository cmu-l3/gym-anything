#!/bin/bash
echo "=== Exporting PSF FWHM Measurement Results ==="

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_end_screenshot.png 2>/dev/null || true

PROJECT_DIR="/home/ga/AstroImages/psf_analysis"
RESULTS_FILE="$PROJECT_DIR/fwhm_results.txt"

START_TIME=$(cat /tmp/task_start_timestamp 2>/dev/null || echo "0")
FILE_EXISTS="false"
CREATED_DURING_TASK="false"

if [ -f "$RESULTS_FILE" ]; then
    FILE_EXISTS="true"
    FILE_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
        CREATED_DURING_TASK="true"
    fi
fi

# Fallback: check if saved in home directory
if [ "$FILE_EXISTS" = "false" ]; then
    if [ -f "/home/ga/fwhm_results.txt" ]; then
        RESULTS_FILE="/home/ga/fwhm_results.txt"
        FILE_EXISTS="true"
        FILE_MTIME=$(stat -c %Y "$RESULTS_FILE" 2>/dev/null || echo "0")
        if [ "$FILE_MTIME" -ge "$START_TIME" ]; then
            CREATED_DURING_TASK="true"
        fi
    fi
fi

if [ "$FILE_EXISTS" = "true" ]; then
    JSON_CONTENT=$(python3 -c "import sys, json; print(json.dumps(sys.stdin.read()))" < "$RESULTS_FILE")
else
    JSON_CONTENT='""'
fi

# Check if AIJ is running
AIJ_RUNNING="false"
if pgrep -f "astroimagej\|aij\|AstroImageJ" > /dev/null; then
    AIJ_RUNNING="true"
fi

cat > /tmp/task_result.json << EOF
{
    "file_exists": $FILE_EXISTS,
    "created_during_task": $CREATED_DURING_TASK,
    "file_content": $JSON_CONTENT,
    "aij_running": $AIJ_RUNNING
}
EOF

# Move to final location safely
chmod 666 /tmp/task_result.json 2>/dev/null || true

echo "=== Export Complete ==="