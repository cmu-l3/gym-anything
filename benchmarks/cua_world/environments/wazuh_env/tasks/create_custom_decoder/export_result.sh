#!/bin/bash
echo "=== Exporting create_custom_decoder results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Configuration Files for Static Analysis
echo "Extracting configuration files..."
docker cp "${CONTAINER}:/var/ossec/etc/decoders/local_decoder.xml" /tmp/final_decoder.xml
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/final_rules.xml

# Set permissions so python verifier can read them
chmod 644 /tmp/final_decoder.xml /tmp/final_rules.xml

# 3. Run Functional Test (wazuh-logtest) inside container
# This is the "Ground Truth" verification - does it actually work?
echo "Running functional verification via wazuh-logtest..."

# Test log line (Failed login)
TEST_LOG_FAILED="Jan 15 10:25:01 bastion-gw session_auth[5236]: user=root src_ip=203.0.113.42 action=login status=failed reason=\"account_locked\""

# Run wazuh-logtest and capture output
# Note: In docker, we pipe the log line into the exec command
LOGTEST_OUTPUT_FAILED=$(echo "$TEST_LOG_FAILED" | docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest 2>&1)

# Test log line (Successful login) - just to check the other rule
TEST_LOG_SUCCESS="Jan 15 10:24:12 bastion-gw session_auth[5235]: user=admin src_ip=10.0.0.5 action=login status=success reason=\"key_auth\""
LOGTEST_OUTPUT_SUCCESS=$(echo "$TEST_LOG_SUCCESS" | docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest 2>&1)

# 4. Check Manager Status
MANAGER_STATUS=$(docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control status 2>&1 || echo "Stopped")

# 5. Check File Timestamps inside container (Anti-gaming)
# We check the mtime of the files inside the container
DECODER_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/decoders/local_decoder.xml 2>/dev/null || echo "0")
RULES_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo "0")

FILES_MODIFIED_DURING_TASK="false"
if [ "$DECODER_MTIME" -gt "$TASK_START" ] || [ "$RULES_MTIME" -gt "$TASK_START" ]; then
    FILES_MODIFIED_DURING_TASK="true"
fi

# 6. Bundle Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
# Use python to safely escape the multiline logtest output
python3 -c "
import json
import os

result = {
    'task_start': $TASK_START,
    'files_modified_during_task': $FILES_MODIFIED_DURING_TASK,
    'manager_status': '''$MANAGER_STATUS''',
    'logtest_output_failed': '''$LOGTEST_OUTPUT_FAILED''',
    'logtest_output_success': '''$LOGTEST_OUTPUT_SUCCESS''',
    'decoder_content': open('/tmp/final_decoder.xml', 'r').read() if os.path.exists('/tmp/final_decoder.xml') else '',
    'rules_content': open('/tmp/final_rules.xml', 'r').read() if os.path.exists('/tmp/final_rules.xml') else '',
    'screenshot_path': '/tmp/task_final.png'
}
print(json.dumps(result))
" > "$TEMP_JSON"

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"
rm -f /tmp/final_decoder.xml /tmp/final_rules.xml

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="