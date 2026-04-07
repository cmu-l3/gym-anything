#!/bin/bash
echo "=== Exporting configure_syslog_forwarding results ==="

TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
DISPLAY=:1 scrot /tmp/task_final.png 2>/dev/null || true

# 2. Get Configuration Content
# We pull the ossec.conf from the container
echo "Extracting ossec.conf..."
OSSEC_CONF_CONTENT=$(docker exec wazuh-wazuh.manager-1 cat /var/ossec/etc/ossec.conf 2>/dev/null || echo "")

# 3. Get Process Status
# We check if wazuh-csyslogd is running
echo "Checking process status..."
PROCESS_STATUS=$(docker exec wazuh-wazuh.manager-1 /var/ossec/bin/wazuh-control status 2>/dev/null || echo "Error getting status")
CSYSLOGD_RUNNING="false"
if echo "$PROCESS_STATUS" | grep -q "wazuh-csyslogd is running"; then
    CSYSLOGD_RUNNING="true"
fi

# 4. Check File Modification Time (Anti-gaming)
# We check the mtime of ossec.conf inside the container
CONFIG_MTIME=$(docker exec wazuh-wazuh.manager-1 stat -c %Y /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")
FILE_MODIFIED_DURING_TASK="false"
if [ "$CONFIG_MTIME" -gt "$TASK_START" ]; then
    FILE_MODIFIED_DURING_TASK="true"
fi

# 5. Create Result JSON
# We treat OSSEC_CONF_CONTENT carefully to ensure valid JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
python3 -c "
import json
import os
import sys

try:
    content = '''$OSSEC_CONF_CONTENT'''
    status = '''$PROCESS_STATUS'''
    
    result = {
        'task_start': $TASK_START,
        'task_end': $TASK_END,
        'config_content': content,
        'process_status_output': status,
        'csyslogd_running': $CSYSLOGD_RUNNING,
        'file_modified_during_task': $FILE_MODIFIED_DURING_TASK,
        'screenshot_path': '/tmp/task_final.png'
    }
    
    with open('$TEMP_JSON', 'w') as f:
        json.dump(result, f)
except Exception as e:
    print(f'Error generating JSON: {e}')
"

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="