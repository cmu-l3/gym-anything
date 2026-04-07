#!/bin/bash
echo "=== Exporting Configure Command Wodle result ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER="wazuh-wazuh.manager-1"
CONFIG_FILE="/var/ossec/etc/ossec.conf"
LOG_FILE="/var/ossec/logs/ossec.log"

# 1. Take final screenshot
take_screenshot /tmp/task_final.png

# 2. Extract the final configuration file
echo "Extracting ossec.conf..."
docker cp "${CONTAINER}:${CONFIG_FILE}" /tmp/final_ossec.conf
# Ensure readable by ga user/verifier
chmod 644 /tmp/final_ossec.conf

# 3. Extract relevant logs (look for command module activity)
echo "Extracting logs..."
# We look for lines containing 'wmodules-command' or the specific tag 'port-audit'
docker exec "${CONTAINER}" grep -E "wmodules-command|port-audit|Executing command" "${LOG_FILE}" > /tmp/wodle_logs.txt 2>/dev/null || touch /tmp/wodle_logs.txt
chmod 644 /tmp/wodle_logs.txt

# 4. Check if Manager is currently running/healthy
MANAGER_STATUS="false"
if check_api_health; then
    MANAGER_STATUS="true"
fi

# 5. Check file modification
INITIAL_MD5=$(cat /tmp/initial_config_md5.txt 2>/dev/null || echo "0")
FINAL_MD5=$(md5sum /tmp/final_ossec.conf 2>/dev/null | awk '{print $1}' || echo "1")

FILE_MODIFIED="false"
if [ "$INITIAL_MD5" != "$FINAL_MD5" ]; then
    FILE_MODIFIED="true"
fi

# 6. Create result JSON
RESULT_JSON="/tmp/task_result.json"
cat > "${RESULT_JSON}" << EOF
{
    "task_start_time": ${TASK_START},
    "manager_running": ${MANAGER_STATUS},
    "config_modified": ${FILE_MODIFIED},
    "config_file_path": "/tmp/final_ossec.conf",
    "log_file_path": "/tmp/wodle_logs.txt",
    "screenshot_path": "/tmp/task_final.png",
    "timestamp": "$(date -Iseconds)"
}
EOF

chmod 666 "${RESULT_JSON}"
echo "Result exported to ${RESULT_JSON}"