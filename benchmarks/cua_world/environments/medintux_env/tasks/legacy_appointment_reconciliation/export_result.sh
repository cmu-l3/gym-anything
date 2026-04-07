#!/bin/bash
echo "=== Exporting task results ==="

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

OUTPUT_READY="/home/ga/Documents/ready_import.csv"
OUTPUT_REVIEW="/home/ga/Documents/review_required.csv"

# Check existence and timestamps
check_file() {
    local f="$1"
    if [ -f "$f" ]; then
        local mtime=$(stat -c %Y "$f" 2>/dev/null || echo "0")
        if [ "$mtime" -gt "$TASK_START" ]; then
            echo "true"
        else
            echo "false"
        fi
    else
        echo "false"
    fi
}

READY_CREATED=$(check_file "$OUTPUT_READY")
REVIEW_CREATED=$(check_file "$OUTPUT_REVIEW")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Prepare files for export (copy to temp to ensure permissions)
cp "$OUTPUT_READY" /tmp/ready_import_export.csv 2>/dev/null || true
cp "$OUTPUT_REVIEW" /tmp/review_required_export.csv 2>/dev/null || true
chmod 666 /tmp/ready_import_export.csv 2>/dev/null || true
chmod 666 /tmp/review_required_export.csv 2>/dev/null || true

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "ready_created": $READY_CREATED,
    "review_created": $REVIEW_CREATED,
    "ready_path": "/tmp/ready_import_export.csv",
    "review_path": "/tmp/review_required_export.csv",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move result json
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"