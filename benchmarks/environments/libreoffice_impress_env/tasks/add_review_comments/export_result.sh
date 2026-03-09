#!/bin/bash
set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Exporting Add Review Comments Result ==="

TARGET_FILE="/home/ga/Documents/Presentations/marketing_strategy.odp"

# Check file modification
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")

MODIFIED="false"
if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
    MODIFIED="true"
fi

FILE_EXISTS="false"
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_modified": $MODIFIED,
    "file_path": "$TARGET_FILE",
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "=== Export complete ==="