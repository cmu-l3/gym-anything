#!/bin/bash
echo "=== Exporting Optimize FIM Noise Reduction results ==="

source /workspace/scripts/task_utils.sh

# Container info
CONTAINER="wazuh-wazuh.manager-1"
CONFIG_PATH="/var/ossec/etc/ossec.conf"
ALERTS_PATH="/var/ossec/logs/alerts/alerts.json"
TARGET_DIR="/var/ossec/etc"

# Files to verify
TEST_FILE_POS="test_alert.xml"
TEST_FILE_NEG="vim_noise.swp"

# 1. Check if test files exist inside container
echo "Checking for test files in container..."
FILES_CHECK_JSON=$(docker exec "$CONTAINER" python3 -c "
import os, json, time
base = '$TARGET_DIR'
files = ['$TEST_FILE_POS', '$TEST_FILE_NEG']
result = {}
for f in files:
    path = os.path.join(base, f)
    exists = os.path.exists(path)
    mtime = 0
    if exists:
        mtime = os.path.getmtime(path)
    result[f] = {'exists': exists, 'mtime': mtime}
print(json.dumps(result))
")

# 2. Extract configuration file
echo "Extracting ossec.conf..."
docker cp "$CONTAINER:$CONFIG_PATH" /tmp/ossec_exported.conf

# 3. Extract alerts (only new ones)
echo "Extracting new alerts..."
INITIAL_LINES=$(cat /tmp/initial_alerts_lines.txt 2>/dev/null || echo "0")
# Use tail to get lines added after setup
# Note: This is an approximation. Ideally we filter by timestamp, but line count is robust enough for short tasks
docker exec "$CONTAINER" tail -n +$((INITIAL_LINES + 1)) "$ALERTS_PATH" > /tmp/new_alerts.json 2>/dev/null || true

# 4. Check if manager process is running
MANAGER_RUNNING=$(docker exec "$CONTAINER" pgrep wazuh-analysisd > /dev/null && echo "true" || echo "false")

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Bundle results into JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# Python script to construct the final JSON to avoid bash quoting hell
python3 -c "
import json
import time

try:
    with open('/tmp/new_alerts.json', 'r') as f:
        # Read line by line as it is ndjson
        alerts_content = [json.loads(line) for line in f if line.strip()]
except:
    alerts_content = []

try:
    with open('/tmp/ossec_exported.conf', 'r') as f:
        config_content = f.read()
except:
    config_content = ''

files_info = json.loads('''$FILES_CHECK_JSON''')

result = {
    'task_start': $TASK_START,
    'task_end': time.time(),
    'manager_running': $MANAGER_RUNNING,
    'ossec_conf': config_content,
    'alerts': alerts_content,
    'files_info': files_info,
    'screenshot_path': '/tmp/task_final.png'
}

print(json.dumps(result))
" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/ossec_exported.conf /tmp/new_alerts.json

echo "Result exported to /tmp/task_result.json"