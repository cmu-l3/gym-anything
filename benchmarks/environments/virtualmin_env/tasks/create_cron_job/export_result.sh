#!/bin/bash
echo "=== Exporting create_cron_job results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TARGET_USER=$(cat /tmp/target_user.txt 2>/dev/null || echo "acmecorp")

# 1. Capture current crontab for target user
CURRENT_CRONTAB=$(crontab -u "$TARGET_USER" -l 2>/dev/null || echo "")

# 2. Capture root crontab (to check for mistakes)
ROOT_CRONTAB=$(crontab -u root -l 2>/dev/null || echo "")

# 3. Check spool file modification
SPOOL_FILE="/var/spool/cron/crontabs/$TARGET_USER"
SPOOL_MODIFIED="false"
if [ -f "$SPOOL_FILE" ]; then
    SPOOL_MTIME=$(stat -c %Y "$SPOOL_FILE" 2>/dev/null || echo "0")
    if [ "$SPOOL_MTIME" -gt "$TASK_START" ]; then
        SPOOL_MODIFIED="true"
    fi
fi

# 4. Capture final screenshot
take_screenshot /tmp/task_final.png

# 5. Create JSON result
# We escape the crontabs to ensure valid JSON
SAFE_CURRENT_CRONTAB=$(json_escape "$CURRENT_CRONTAB")
SAFE_ROOT_CRONTAB=$(json_escape "$ROOT_CRONTAB")

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "target_user": "$TARGET_USER",
    "spool_modified": $SPOOL_MODIFIED,
    "user_crontab": "$SAFE_CURRENT_CRONTAB",
    "root_crontab": "$SAFE_ROOT_CRONTAB",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "=== Export complete ==="