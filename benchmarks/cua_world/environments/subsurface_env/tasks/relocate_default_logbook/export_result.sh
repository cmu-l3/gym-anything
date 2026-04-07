#!/bin/bash
set -euo pipefail
echo "=== Exporting relocate_default_logbook result ==="

export DISPLAY="${DISPLAY:-:1}"

# Take final screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_final.png 2>/dev/null || true

TARGET_DIR="/home/ga/Sync/DiveLogs"
TARGET_FILE="$TARGET_DIR/main_log.ssrf"
CONFIG_FILE="/home/ga/.config/Subsurface/Subsurface.conf"

# Check directory existence
DIR_EXISTS="false"
if [ -d "$TARGET_DIR" ]; then 
    DIR_EXISTS="true"
fi

# Check file existence and size
FILE_EXISTS="false"
FILE_SIZE=0
if [ -f "$TARGET_FILE" ]; then
    FILE_EXISTS="true"
    FILE_SIZE=$(stat -c%s "$TARGET_FILE" 2>/dev/null || echo 0)
fi

# Extract DefaultFilename from config
DEFAULT_FILENAME=""
if [ -f "$CONFIG_FILE" ]; then
    RAW_CONFIG=$(grep -i "^DefaultFilename=" "$CONFIG_FILE" | head -n 1 | cut -d'=' -f2- || true)
    # Trim leading/trailing whitespace securely
    DEFAULT_FILENAME=$(echo "$RAW_CONFIG" | awk '{$1=$1};1')
fi

# Create JSON result securely
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "dir_exists": $DIR_EXISTS,
    "file_exists": $FILE_EXISTS,
    "file_size_bytes": $FILE_SIZE,
    "configured_default_file": "$DEFAULT_FILENAME"
}
EOF

# Move to final destination
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json:"
cat /tmp/task_result.json

echo "=== Export complete ==="