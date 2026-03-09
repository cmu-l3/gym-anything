#!/bin/bash
echo "=== Exporting task results: disable_ssh_root_login ==="

# Source shared utilities for screenshot
source /workspace/scripts/task_utils.sh

# Record task end time
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
INITIAL_CONFIG_MTIME=$(cat /tmp/initial_config_mtime.txt 2>/dev/null || echo "0")
SSHD_CONFIG="/etc/ssh/sshd_config"

# 1. Check Runtime Configuration (Crucial: Did they apply the change?)
# 'sshd -T' outputs the effective configuration
# We look for 'permitrootlogin no'
RUNTIME_CONFIG_CORRECT="false"
if sudo sshd -T 2>/dev/null | grep -qi "permitrootlogin no"; then
    RUNTIME_CONFIG_CORRECT="true"
fi

# 2. Check Static File Configuration
# Did they edit the file correctly?
FILE_CONFIG_CORRECT="false"
if grep -q "^PermitRootLogin no" "$SSHD_CONFIG"; then
    FILE_CONFIG_CORRECT="true"
fi

# 3. Check for "Do Nothing" (Timestamp check)
CONFIG_MODIFIED="false"
CURRENT_CONFIG_MTIME=$(stat -c %Y "$SSHD_CONFIG" 2>/dev/null || echo "0")

# It counts as modified if the mtime is greater than the setup time
if [ "$CURRENT_CONFIG_MTIME" -gt "$INITIAL_CONFIG_MTIME" ] && [ "$CURRENT_CONFIG_MTIME" -ge "$TASK_START" ]; then
    CONFIG_MODIFIED="true"
fi

# 4. Check if service is running
SERVICE_RUNNING="false"
if systemctl is-active --quiet sshd; then
    SERVICE_RUNNING="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "runtime_config_correct": $RUNTIME_CONFIG_CORRECT,
    "file_config_correct": $FILE_CONFIG_CORRECT,
    "config_modified_during_task": $CONFIG_MODIFIED,
    "service_running": $SERVICE_RUNNING,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="