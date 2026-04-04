#!/bin/bash
set -e
echo "=== Exporting create_techdraw results ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Paths
OUTPUT_FCSTD="/home/ga/Documents/FreeCAD/T8_bracket_drawing.FCStd"
OUTPUT_PDF="/home/ga/Documents/FreeCAD/T8_bracket_drawing.pdf"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Take final screenshot
take_screenshot /tmp/task_final_state.png

# Initialize result variables
FCSTD_EXISTS="false"
FCSTD_SIZE="0"
FCSTD_CREATED_DURING_TASK="false"
PDF_EXISTS="false"
PDF_SIZE="0"
PDF_CREATED_DURING_TASK="false"
APP_RUNNING="false"

# Check FCStd file
if [ -f "$OUTPUT_FCSTD" ]; then
    FCSTD_EXISTS="true"
    FCSTD_SIZE=$(stat -c%s "$OUTPUT_FCSTD" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_FCSTD" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FCSTD_CREATED_DURING_TASK="true"
    fi
fi

# Check PDF file
if [ -f "$OUTPUT_PDF" ]; then
    PDF_EXISTS="true"
    PDF_SIZE=$(stat -c%s "$OUTPUT_PDF" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c%Y "$OUTPUT_PDF" 2>/dev/null || echo "0")
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        PDF_CREATED_DURING_TASK="true"
    fi
fi

# Check if FreeCAD is still running
if pgrep -f "freecad" > /dev/null; then
    APP_RUNNING="true"
fi

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_was_running": $APP_RUNNING,
    "fcstd_exists": $FCSTD_EXISTS,
    "fcstd_size_bytes": $FCSTD_SIZE,
    "fcstd_created_during_task": $FCSTD_CREATED_DURING_TASK,
    "fcstd_path": "$OUTPUT_FCSTD",
    "pdf_exists": $PDF_EXISTS,
    "pdf_size_bytes": $PDF_SIZE,
    "pdf_created_during_task": $PDF_CREATED_DURING_TASK,
    "pdf_path": "$OUTPUT_PDF",
    "screenshot_path": "/tmp/task_final_state.png"
}
EOF

# Save result to known location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 644 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="