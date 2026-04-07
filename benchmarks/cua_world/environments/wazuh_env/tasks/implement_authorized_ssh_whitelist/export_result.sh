#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Capture Configuration Files
echo "Capturing configuration files..."
docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf > /tmp/exported_ossec.conf 2>/dev/null || echo "ossec.conf missing" > /tmp/exported_ossec.conf
docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml > /tmp/exported_local_rules.xml 2>/dev/null || echo "local_rules.xml missing" > /tmp/exported_local_rules.xml

# Capture list file content
docker exec "${CONTAINER}" cat /var/ossec/etc/lists/authorized_users > /tmp/exported_list_content.txt 2>/dev/null || echo "list file missing" > /tmp/exported_list_content.txt

# Check if .cdb compiled file exists
LIST_CDB_EXISTS=$(docker exec "${CONTAINER}" [ -f /var/ossec/etc/lists/authorized_users.cdb ] && echo "true" || echo "false")

# 2. Functional Verification using wazuh-logtest
# We will inject the test logs into wazuh-logtest inside the container and capture the JSON output.

echo "Running functional verification via wazuh-logtest..."

# Test Case A: Authorized User 'ga' (Should NOT trigger rule 100500)
LOG_AUTH="Dec 10 10:00:00 server sshd[1234]: Accepted password for ga from 192.168.1.100 port 22 ssh2"
TEST_RESULT_AUTH=$(docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest <<< "$LOG_AUTH" 2>/dev/null)

# Test Case B: Unauthorized User 'intruder' (SHOULD trigger rule 100500)
LOG_UNAUTH="Dec 10 10:05:00 server sshd[1235]: Accepted password for intruder from 192.168.1.101 port 22 ssh2"
TEST_RESULT_UNAUTH=$(docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest <<< "$LOG_UNAUTH" 2>/dev/null)

# 3. Gather evidence into JSON
# Use a python script to parse the logtest output text (which is semi-structured/JSON-like)
# Wazuh-logtest output in 4.x is JSON if configured, but default interactive mode outputs text.
# We will look for specific strings in the output.

# Helper to check rule ID in output
check_rule_hit() {
    local output="$1"
    local rule_id="$2"
    if echo "$output" | grep -q "Rule: $rule_id"; then
        echo "true"
    else
        echo "false"
    fi
}

AUTH_HIT_100500=$(check_rule_hit "$TEST_RESULT_AUTH" "100500")
UNAUTH_HIT_100500=$(check_rule_hit "$TEST_RESULT_UNAUTH" "100500")
AUTH_HIT_5715=$(check_rule_hit "$TEST_RESULT_AUTH" "5715")

# Capture list file timestamp to verify creation during task
LIST_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/lists/authorized_users 2>/dev/null || echo "0")
FILE_CREATED_DURING_TASK="false"
if [ "$LIST_MTIME" -gt "$TASK_START" ]; then
    FILE_CREATED_DURING_TASK="true"
fi

# Take final screenshot
take_screenshot /tmp/task_final.png

# Create final JSON result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "list_cdb_exists": $LIST_CDB_EXISTS,
    "list_file_created_during_task": $FILE_CREATED_DURING_TASK,
    "functional_test": {
        "authorized_log": "$LOG_AUTH",
        "unauthorized_log": "$LOG_UNAUTH",
        "auth_triggers_100500": $AUTH_HIT_100500,
        "auth_triggers_5715": $AUTH_HIT_5715,
        "unauth_triggers_100500": $UNAUTH_HIT_100500,
        "raw_result_auth": $(echo "$TEST_RESULT_AUTH" | jq -R -s .),
        "raw_result_unauth": $(echo "$TEST_RESULT_UNAUTH" | jq -R -s .)
    },
    "config_content": {
        "ossec_conf": $(jq -R -s . < /tmp/exported_ossec.conf),
        "local_rules": $(jq -R -s . < /tmp/exported_local_rules.xml),
        "list_content": $(jq -R -s . < /tmp/exported_list_content.txt)
    },
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
echo "=== Export complete ==="