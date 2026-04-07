#!/bin/bash
# export_result.sh for implement_compromised_credential_detection

set -e
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

# Files to check
LIST_SOURCE="/var/ossec/etc/lists/compromised_users"
LIST_CDB="/var/ossec/etc/lists/compromised_users.cdb"
CONFIG_FILE="/var/ossec/etc/ossec.conf"
RULES_FILE="/var/ossec/etc/rules/local_rules.xml"
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Check file existence in container
echo "Checking files in container..."
SOURCE_EXISTS=$(docker exec "$CONTAINER" [ -f "$LIST_SOURCE" ] && echo "true" || echo "false")
CDB_EXISTS=$(docker exec "$CONTAINER" [ -f "$LIST_CDB" ] && echo "true" || echo "false")
CONFIG_CONTAINS_LIST=$(docker exec "$CONTAINER" grep -q "<list>etc/lists/compromised_users</list>" "$CONFIG_FILE" && echo "true" || echo "false")

# 2. Extract Rule Content
echo "Reading rules file..."
RULES_CONTENT=$(docker exec "$CONTAINER" cat "$RULES_FILE" | base64 -w 0)

# 3. Read Source List Content
echo "Reading source list..."
SOURCE_CONTENT=""
if [ "$SOURCE_EXISTS" = "true" ]; then
    SOURCE_CONTENT=$(docker exec "$CONTAINER" cat "$LIST_SOURCE" | base64 -w 0)
fi

# 4. Verify Logic via wazuh-logtest (The most critical check)
echo "Running wazuh-logtest verification..."

# Test Case 1: Positive (User 'admin' is in the breached list)
# Standard SSH success log for admin
LOG_POSITIVE="Jul 10 12:00:00 server sshd[1234]: Accepted password for admin from 192.168.1.1 port 22 ssh2"
# JSON input for logtest
JSON_POSITIVE="{\"log\": \"$LOG_POSITIVE\"}"

# Run logtest inside container
LOGTEST_OUT_POSITIVE=$(echo "$JSON_POSITIVE" | docker exec -i "$CONTAINER" /var/ossec/bin/wazuh-logtest 2>&1)
echo "Positive Test Output:"
echo "$LOGTEST_OUT_POSITIVE"

# Check if rule 100050 triggered
POSITIVE_TRIGGERED=$(echo "$LOGTEST_OUT_POSITIVE" | grep -q '"id": "100050"' && echo "true" || echo "false")

# Test Case 2: Negative (User 'safe_user' is NOT in the list)
LOG_NEGATIVE="Jul 10 12:00:00 server sshd[1234]: Accepted password for safe_user from 192.168.1.1 port 22 ssh2"
JSON_NEGATIVE="{\"log\": \"$LOG_NEGATIVE\"}"

LOGTEST_OUT_NEGATIVE=$(echo "$JSON_NEGATIVE" | docker exec -i "$CONTAINER" /var/ossec/bin/wazuh-logtest 2>&1)
echo "Negative Test Output:"
echo "$LOGTEST_OUT_NEGATIVE"

# Check if rule 100050 triggered (Should NOT trigger)
NEGATIVE_TRIGGERED=$(echo "$LOGTEST_OUT_NEGATIVE" | grep -q '"id": "100050"' && echo "true" || echo "false")
# Check if parent rule 5715 triggered (Should trigger for valid login)
PARENT_TRIGGERED=$(echo "$LOGTEST_OUT_NEGATIVE" | grep -q '"id": "5715"' && echo "true" || echo "false")


# 5. Capture final screenshot
take_screenshot /tmp/task_final.png


# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "source_exists": $SOURCE_EXISTS,
    "cdb_exists": $CDB_EXISTS,
    "config_contains_list": $CONFIG_CONTAINS_LIST,
    "rules_content_b64": "$RULES_CONTENT",
    "source_content_b64": "$SOURCE_CONTENT",
    "logic_test": {
        "positive_triggered": $POSITIVE_TRIGGERED,
        "negative_triggered": $NEGATIVE_TRIGGERED,
        "parent_triggered": $PARENT_TRIGGERED
    },
    "timestamp": "$(date +%s)"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat /tmp/task_result.json