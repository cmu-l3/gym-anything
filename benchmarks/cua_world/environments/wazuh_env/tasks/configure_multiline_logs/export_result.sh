#!/bin/bash
echo "=== Exporting Configure Multiline Logs result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
RESULT_JSON="/tmp/task_result.json"
TEST_ID="TEST_$(date +%s)"

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Functional Test: Inject a multi-line log
# We inject a log with 3 lines. 
# If configured correctly, it should appear as 1 event in archives.log.
# If configured incorrectly (syslog default), it will appear as 3 events.
echo "Injecting test log entry..."
docker exec "${CONTAINER}" bash -c "cat >> /var/log/billing_app.log <<EOF
2023-12-01 12:00:00 ERROR Billing - ${TEST_ID}
java.lang.NullPointerException: null
    at com.billing.Processor.run(Processor.java:42)
EOF"

# Wait for ingestion
sleep 10

# 3. Read ossec.conf for static verification
echo "Reading ossec.conf..."
docker cp "${CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec_export.conf

# 4. Check archives.log for the test entry
# We grep for the TEST_ID and context
echo "Checking archives.log..."
docker exec "${CONTAINER}" grep -A 5 "${TEST_ID}" /var/ossec/logs/archives/archives.log > /tmp/archives_grep.txt 2>/dev/null || echo "Log not found" > /tmp/archives_grep.txt

# 5. Check if manager is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" pgrep wazuh-modulesd > /dev/null; then
    MANAGER_RUNNING="true"
fi

# 6. Prepare data for JSON
# Read conf file content (escape quotes for JSON)
CONF_CONTENT=$(cat /tmp/ossec_export.conf | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')
ARCHIVES_CONTENT=$(cat /tmp/archives_grep.txt | python3 -c 'import sys, json; print(json.dumps(sys.stdin.read()))')

# 7. Create JSON result
cat > "${RESULT_JSON}" << EOF
{
    "ossec_conf": $CONF_CONTENT,
    "archives_grep": $ARCHIVES_CONTENT,
    "test_id": "${TEST_ID}",
    "manager_running": ${MANAGER_RUNNING},
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 "${RESULT_JSON}"

echo "Result exported to ${RESULT_JSON}"