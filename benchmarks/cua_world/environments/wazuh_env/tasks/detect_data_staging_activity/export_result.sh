#!/bin/bash
echo "=== Exporting detect_data_staging_activity result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_JSON="/tmp/task_result.json"
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)

# Define the logs to test
MALICIOUS_LOG='type=EXECVE msg=audit(1698234001.123:101): argc=4 a0="tar" a1="-czf" a2="/tmp/backup_sensitive.tar.gz" a3="/opt/sensitive_project"'
BENIGN_LOG='type=EXECVE msg=audit(1698234055.456:102): argc=4 a0="tar" a1="-czf" a2="/tmp/my_docs.tar.gz" a3="/home/user/documents"'

# 1. Check if Rule 100250 exists in local_rules.xml
echo "Checking local_rules.xml..."
RULES_CONTENT=$(docker exec "$CONTAINER" cat /var/ossec/etc/rules/local_rules.xml 2>/dev/null || echo "")

RULE_EXISTS="false"
if echo "$RULES_CONTENT" | grep -q 'id="100250"'; then
    RULE_EXISTS="true"
fi

RULE_LEVEL=$(echo "$RULES_CONTENT" | grep 'id="100250"' | grep -o 'level="[^"]*"' | cut -d'"' -f2 || echo "0")

# 2. Run wazuh-logtest to verify behavior
echo "Running wazuh-logtest..."

# Test Malicious Log
# We pipe the log to wazuh-logtest and grep for the rule ID firing
TEST_MALICIOUS=$(docker exec -i "$CONTAINER" /var/ossec/bin/wazuh-logtest 2>&1 <<EOF
$MALICIOUS_LOG
EOF
)

DETECTS_MALICIOUS="false"
if echo "$TEST_MALICIOUS" | grep -q "Rule.*100250.*fired"; then
    DETECTS_MALICIOUS="true"
fi

# Test Benign Log
TEST_BENIGN=$(docker exec -i "$CONTAINER" /var/ossec/bin/wazuh-logtest 2>&1 <<EOF
$BENIGN_LOG
EOF
)

IGNORES_BENIGN="true"
if echo "$TEST_BENIGN" | grep -q "Rule.*100250.*fired"; then
    IGNORES_BENIGN="false"
fi

# 3. Check regex content (heuristic)
CONTAINS_TAR="false"
CONTAINS_PATH="false"
if echo "$RULES_CONTENT" | grep -q "tar"; then CONTAINS_TAR="true"; fi
if echo "$RULES_CONTENT" | grep -q "sensitive_project"; then CONTAINS_PATH="true"; fi

# 4. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 5. Build JSON Result
cat > "$TEMP_JSON" << EOF
{
    "rule_exists": $RULE_EXISTS,
    "rule_level": "$RULE_LEVEL",
    "detects_malicious": $DETECTS_MALICIOUS,
    "ignores_benign": $IGNORES_BENIGN,
    "contains_tar": $CONTAINS_TAR,
    "contains_path": $CONTAINS_PATH,
    "timestamp": "$(date -Iseconds)",
    "logtest_output_malicious_sample": "$(echo "$TEST_MALICIOUS" | head -n 20 | sed 's/"/\\"/g' | tr '\n' ' ')",
    "rules_content_snippet": "$(echo "$RULES_CONTENT" | grep -A 5 'id="100250"' | sed 's/"/\\"/g' | tr '\n' ' ')"
}
EOF

# Save result safely
rm -f "$RESULT_JSON" 2>/dev/null || sudo rm -f "$RESULT_JSON" 2>/dev/null || true
cp "$TEMP_JSON" "$RESULT_JSON" 2>/dev/null || sudo cp "$TEMP_JSON" "$RESULT_JSON"
chmod 666 "$RESULT_JSON" 2>/dev/null || sudo chmod 666 "$RESULT_JSON" 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Export complete. Result:"
cat "$RESULT_JSON"