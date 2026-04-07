#!/bin/bash
echo "=== Exporting monitor_config_diffs result ==="

source /workspace/scripts/task_utils.sh

# Record timestamps
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

CONTAINER="wazuh-wazuh.manager-1"
TARGET_FILE="/var/ossec/etc/critical_app.conf"

# 1. Capture Config State
echo "Reading ossec.conf..."
OSSEC_CONF_SNIPPET=$(docker exec "$CONTAINER" grep -C 2 "$TARGET_FILE" /var/ossec/etc/ossec.conf 2>/dev/null || echo "not_found")

# 2. Capture File Content
echo "Reading target file content..."
FILE_CONTENT=$(docker exec "$CONTAINER" cat "$TARGET_FILE" 2>/dev/null || echo "file_missing")

# 3. Capture Alerts
# We look for alerts generated AFTER task start
echo "Parsing alerts.json..."
# Create a python script to parse the alerts log inside the container (or pipe it out)
# We'll pipe it out to a local temp file first to avoid complex escaping
docker exec "$CONTAINER" tail -n 2000 /var/ossec/logs/alerts/alerts.json > /tmp/recent_alerts.json 2>/dev/null || true

# Filter alerts in python on the host
cat > /tmp/parse_alerts.py << PYEOF
import json
import sys

target_file = "$TARGET_FILE"
task_start = $TASK_START
found_alert = False
diff_content = None

try:
    with open('/tmp/recent_alerts.json', 'r') as f:
        for line in f:
            try:
                alert = json.loads(line)
                # Check timestamp (Wazuh logs usually have 'timestamp' string, we rely on file tailing for approximation or parse if possible)
                # Ideally check alert['timestamp'] which is ISO8601
                
                # Check if it's a FIM alert for our file
                if 'syscheck' in alert and 'path' in alert['syscheck']:
                    if alert['syscheck']['path'] == target_file:
                        found_alert = True
                        if 'diff' in alert['syscheck']:
                            diff_content = alert['syscheck']['diff']
            except ValueError:
                continue
except Exception as e:
    sys.stderr.write(str(e))

result = {
    "alert_found": found_alert,
    "diff_found": diff_content is not None,
    "diff_preview": diff_content[:100] if diff_content else ""
}
print(json.dumps(result))
PYEOF

ALERT_RESULT=$(python3 /tmp/parse_alerts.py)

# 4. Take Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "config_snippet": $(echo "$OSSEC_CONF_SNIPPET" | jq -R -s '.'),
    "file_content": $(echo "$FILE_CONTENT" | jq -R -s '.'),
    "alert_analysis": $ALERT_RESULT,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON" /tmp/recent_alerts.json /tmp/parse_alerts.py

echo "Export complete. Result:"
cat /tmp/task_result.json