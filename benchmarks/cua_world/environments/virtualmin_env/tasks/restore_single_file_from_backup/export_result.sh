#!/bin/bash
echo "=== Exporting restore_single_file_from_backup result ==="

# Source utilities
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

WEB_DIR="/home/acmecorp/public_html"
TARGET_FILE="$WEB_DIR/pricing.pdf"
PROTECTED_FILE="$WEB_DIR/index.html"

# Check Target File (pricing.pdf)
TARGET_EXISTS="false"
TARGET_MD5=""
TARGET_MTIME=0

if [ -f "$TARGET_FILE" ]; then
    TARGET_EXISTS="true"
    TARGET_MD5=$(md5sum "$TARGET_FILE" | awk '{print $1}')
    TARGET_MTIME=$(stat -c %Y "$TARGET_FILE" 2>/dev/null || echo "0")
fi

# Check Protected File (index.html)
PROTECTED_EXISTS="false"
PROTECTED_MD5=""
PROTECTED_MTIME=0

if [ -f "$PROTECTED_FILE" ]; then
    PROTECTED_EXISTS="true"
    PROTECTED_MD5=$(md5sum "$PROTECTED_FILE" | awk '{print $1}')
    PROTECTED_MTIME=$(stat -c %Y "$PROTECTED_FILE" 2>/dev/null || echo "0")
fi

# Determine if protected file was overwritten (timestamp check)
# If PROTECTED_MTIME > TASK_START, it might have been restored (overwritten) OR manually edited.
# The MD5 check in python verifier is more robust, but we capture the time here.

# Capture Firefox state (app running check)
FIREFOX_RUNNING=$(pgrep -f "firefox" > /dev/null && echo "true" || echo "false")

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "target_exists": $TARGET_EXISTS,
    "target_md5": "$TARGET_MD5",
    "target_mtime": $TARGET_MTIME,
    "protected_exists": $PROTECTED_EXISTS,
    "protected_md5": "$PROTECTED_MD5",
    "protected_mtime": $PROTECTED_MTIME,
    "app_was_running": $FIREFOX_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="