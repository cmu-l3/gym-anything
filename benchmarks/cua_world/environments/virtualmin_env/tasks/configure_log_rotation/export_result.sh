#!/bin/bash
echo "=== Exporting configure_log_rotation result ==="

source /workspace/scripts/task_utils.sh

# 1. Capture final screenshot
take_screenshot /tmp/task_final.png

# 2. Locate the logrotate configuration
# Virtualmin usually puts domain logs in /etc/logrotate.d/virtualmin.conf
# or sometimes split files. We'll search for the file containing our log path.
LOG_PATH="/var/log/virtualmin/acmecorp.test_access_log"
CONFIG_FILE=$(grep -l "$LOG_PATH" /etc/logrotate.d/* 2>/dev/null | head -1)

if [ -z "$CONFIG_FILE" ]; then
    echo "WARNING: Could not find logrotate config for $LOG_PATH"
    CONFIG_FOUND="false"
    CONFIG_CONTENT=""
else
    echo "Found config at $CONFIG_FILE"
    CONFIG_FOUND="true"
    CONFIG_CONTENT=$(cat "$CONFIG_FILE")
    # Copy for verifier
    cp "$CONFIG_FILE" /tmp/final_logrotate.conf
    chmod 644 /tmp/final_logrotate.conf
fi

# 3. Check modification time
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
FILE_MODIFIED="false"
if [ "$CONFIG_FOUND" = "true" ]; then
    MOD_TIME=$(stat -c %Y "$CONFIG_FILE" 2>/dev/null || echo "0")
    if [ "$MOD_TIME" -gt "$TASK_START" ]; then
        FILE_MODIFIED="true"
    fi
fi

# 4. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "config_found": $CONFIG_FOUND,
    "config_file_path": "$CONFIG_FILE",
    "file_modified_during_task": $FILE_MODIFIED,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Export complete."