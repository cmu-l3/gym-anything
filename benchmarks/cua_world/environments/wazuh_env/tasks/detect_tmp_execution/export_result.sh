#!/bin/bash
echo "=== Exporting detect_tmp_execution results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture local_rules.xml
echo "Exporting local_rules.xml..."
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules.xml 2>/dev/null || echo "Failed to copy local_rules.xml"

# 2. Capture ossec.conf
echo "Exporting ossec.conf..."
docker cp "${CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec.conf 2>/dev/null || echo "Failed to copy ossec.conf"

# 3. Capture alerts.json (last 1000 lines to keep it small)
echo "Exporting alerts.json..."
docker exec "${CONTAINER}" tail -n 1000 /var/ossec/logs/alerts/alerts.json > /tmp/alerts.json 2>/dev/null || echo "Failed to copy alerts.json"

# 4. Check if replay.log was modified
REPLAY_LOG_SIZE=$(docker exec "${CONTAINER}" stat -c %s /root/replay.log 2>/dev/null || echo "0")
REPLAY_LOG_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /root/replay.log 2>/dev/null || echo "0")

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "replay_log_size": $REPLAY_LOG_SIZE,
    "replay_log_mtime": $REPLAY_LOG_MTIME,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move files to final export location
# We create a tarball of the config files to keep things clean for the verifier, 
# or just rely on verifier reading them from /tmp if we use copy_from_env on specific paths.
# To fit the standard pattern, we'll put the file contents INTO the json or verify separate files.
# The standard verifier pattern uses copy_from_env. Let's make the JSON comprehensive.

# Read file contents into python to safely dump to JSON
python3 -c "
import json
import os
import sys

def read_file(path):
    if os.path.exists(path):
        with open(path, 'r', errors='ignore') as f:
            return f.read()
    return ''

result = json.load(open('$TEMP_JSON'))
result['local_rules_content'] = read_file('/tmp/local_rules.xml')
result['ossec_conf_content'] = read_file('/tmp/ossec.conf')
result['alerts_json_content'] = read_file('/tmp/alerts.json')

with open('/tmp/task_result.json', 'w') as f:
    json.dump(result, f)
"

# Clean up temp files
rm -f "$TEMP_JSON" /tmp/local_rules.xml /tmp/ossec.conf /tmp/alerts.json

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="