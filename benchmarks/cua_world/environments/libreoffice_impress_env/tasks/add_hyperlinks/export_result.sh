#!/bin/bash
set -euo pipefail

echo "=== Exporting Add Hyperlinks Result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Define paths
ODP_FILE="/home/ga/Documents/Presentations/community_resources.odp"
PPTX_FILE="/home/ga/Documents/Presentations/community_resources.pptx"

# Capture final screenshot
echo "Capturing final state..."
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# Determine which file to check (ODP preferred, PPTX fallback)
TARGET_FILE=""
FILE_FORMAT=""
if [ -f "$ODP_FILE" ]; then
    TARGET_FILE="$ODP_FILE"
    FILE_FORMAT="odp"
elif [ -f "$PPTX_FILE" ]; then
    TARGET_FILE="$PPTX_FILE"
    FILE_FORMAT="pptx"
fi

# Gather file statistics
FILE_EXISTS="false"
FILE_SIZE_BYTES=0
FILE_MODIFIED="false"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_HASH=$(cat /tmp/initial_file_hash.txt 2>/dev/null || echo "")

if [ -n "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE_BYTES=$(stat -c %s "$TARGET_FILE" 2>/dev/null || echo "0")
    FILE_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
    
    # Check modification time
    if [ "$FILE_MTIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
    
    # Check hash change if timestamp is ambiguous
    CURRENT_HASH=$(md5sum "$TARGET_FILE" 2>/dev/null | awk '{print $1}' || echo "")
    if [ "$CURRENT_HASH" != "$INITIAL_HASH" ] && [ -n "$INITIAL_HASH" ]; then
        FILE_MODIFIED="true"
    fi
fi

# Check if Impress is still running
APP_RUNNING="false"
if pgrep -f "soffice.bin" > /dev/null; then
    APP_RUNNING="true"
fi

# Prepare result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "file_exists": $FILE_EXISTS,
    "file_path": "$TARGET_FILE",
    "file_format": "$FILE_FORMAT",
    "file_modified": $FILE_MODIFIED,
    "file_size_bytes": $FILE_SIZE_BYTES,
    "app_running": $APP_RUNNING,
    "task_start_time": $TASK_START,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move result to final location
chmod 644 "$TEMP_JSON"
mv "$TEMP_JSON" /tmp/task_result.json

# If we have a target file, ensure it's readable by the user running verification (host)
if [ -n "$TARGET_FILE" ]; then
    cp "$TARGET_FILE" /tmp/final_presentation.$FILE_FORMAT
    chmod 644 /tmp/final_presentation.$FILE_FORMAT
fi

echo "=== Export complete ==="