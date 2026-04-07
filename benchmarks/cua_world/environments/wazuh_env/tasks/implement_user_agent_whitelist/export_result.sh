#!/bin/bash
# Export results for implement_user_agent_whitelist task

echo "=== Exporting Task Results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# Take final screenshot
take_screenshot /tmp/task_final.png

# --- Verification Step 1: Check List File ---
echo "Checking list file..."
LIST_EXISTS="false"
LIST_CONTENT=""
if docker exec "${CONTAINER}" test -f /var/ossec/etc/lists/authorized_user_agents; then
    LIST_EXISTS="true"
    LIST_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/lists/authorized_user_agents | base64 -w 0)
fi

# --- Verification Step 2: Check CDB Compilation ---
echo "Checking CDB file..."
CDB_EXISTS="false"
if docker exec "${CONTAINER}" test -f /var/ossec/etc/lists/authorized_user_agents.cdb; then
    CDB_EXISTS="true"
    # Check timestamp to ensure it was compiled DURING the task
    CDB_MTIME=$(docker exec "${CONTAINER}" stat -c %Y /var/ossec/etc/lists/authorized_user_agents.cdb)
    if [ "$CDB_MTIME" -gt "$TASK_START" ]; then
        CDB_NEWLY_COMPILED="true"
    else
        CDB_NEWLY_COMPILED="false"
    fi
else
    CDB_NEWLY_COMPILED="false"
fi

# --- Verification Step 3: Check ossec.conf configuration ---
echo "Checking ossec.conf..."
OSSEC_CONF_CHECK="false"
if docker exec "${CONTAINER}" grep -q "etc/lists/authorized_user_agents" /var/ossec/etc/ossec.conf; then
    OSSEC_CONF_CHECK="true"
fi

# --- Verification Step 4: Check local_rules.xml content ---
echo "Checking local_rules.xml..."
RULES_CONTENT=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml | base64 -w 0)

# --- Verification Step 5: Functional Test via logtest ---
echo "Running functional test..."
# We simulate a log line that SHOULD trigger the rule if implemented correctly
# Nginx log with unauthorized user agent
TEST_LOG='192.168.1.50 - - [28/Oct/2023:10:00:00 +0000] "GET /api/v1/resource HTTP/1.1" 200 123 "-" "EvilScanner/1.0"'

# Run logtest inside container
# We pipe the log line into wazuh-logtest and capture the JSON output
LOGTEST_OUTPUT=$(docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest <<< "$TEST_LOG" 2>&1)
LOGTEST_JSON=$(echo "$LOGTEST_OUTPUT" | grep -A 100 "output" || echo "")

# Check if Rule 100200 fired
RULE_FIRED="false"
if echo "$LOGTEST_OUTPUT" | grep -q "100200"; then
    RULE_FIRED="true"
fi

# Check positive case (Authorized agent should NOT fire)
TEST_LOG_GOOD='192.168.1.50 - - [28/Oct/2023:10:00:00 +0000] "GET /api/v1/resource HTTP/1.1" 200 123 "-" "InternalTool/1.0"'
LOGTEST_OUTPUT_GOOD=$(docker exec -i "${CONTAINER}" /var/ossec/bin/wazuh-logtest <<< "$TEST_LOG_GOOD" 2>&1)
RULE_FIRED_GOOD="false"
if echo "$LOGTEST_OUTPUT_GOOD" | grep -q "100200"; then
    RULE_FIRED_GOOD="true" # This is bad, it shouldn't fire
fi

# Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "list_exists": $LIST_EXISTS,
    "list_content_b64": "$LIST_CONTENT",
    "cdb_exists": $CDB_EXISTS,
    "cdb_newly_compiled": $CDB_NEWLY_COMPILED,
    "ossec_conf_has_list": $OSSEC_CONF_CHECK,
    "rules_content_b64": "$RULES_CONTENT",
    "functional_test_fired_bad": $RULE_FIRED,
    "functional_test_fired_good": $RULE_FIRED_GOOD,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete."
cat /tmp/task_result.json