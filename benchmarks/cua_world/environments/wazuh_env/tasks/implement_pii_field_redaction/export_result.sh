#!/bin/bash
set -e
echo "=== Exporting PII Redaction Result ==="

source /workspace/scripts/task_utils.sh

WAZUH_MANAGER="wazuh-wazuh.manager-1"
TEST_ID="VERIFY-PII-$(date +%s)"
TEST_CC="4111-2222-3333-4444"
TEST_AMOUNT=999.99

# 1. Inject a specific verification marker log
echo "Injecting verification marker log..."
VERIFY_JSON="{\"event\":\"verification\", \"test_id\":\"$TEST_ID\", \"amount\":$TEST_AMOUNT, \"cc_number\":\"$TEST_CC\", \"status\":\"verify\"}"
docker exec "$WAZUH_MANAGER" sh -c "echo '$VERIFY_JSON' >> /var/ossec/logs/payments.json"

# 2. Wait for ingestion (Filebeat -> Indexer pipeline)
echo "Waiting for log ingestion (30s)..."
sleep 30

# 3. Query the Indexer for the marker
# We search for the unique test_id
echo "Querying Indexer for marker..."
INDEXER_QUERY="{\"query\": {\"match\": {\"data.test_id\": \"$TEST_ID\"}}}"

QUERY_RESULT=$(wazuh_indexer_query "/_search" "$INDEXER_QUERY")
echo "Indexer Query Result: $QUERY_RESULT"

# 4. Check Filebeat configuration content
echo "Reading Filebeat configuration..."
FILEBEAT_CONFIG=$(docker exec "$WAZUH_MANAGER" cat /etc/filebeat/filebeat.yml 2>/dev/null || echo "CONFIG_NOT_FOUND")

# 5. Check Filebeat service status
FILEBEAT_STATUS="unknown"
if docker exec "$WAZUH_MANAGER" service filebeat status 2>/dev/null | grep -q "running"; then
    FILEBEAT_STATUS="running"
else
    # Try alternative check
    if docker exec "$WAZUH_MANAGER" pgrep filebeat >/dev/null; then
        FILEBEAT_STATUS="running"
    else
        FILEBEAT_STATUS="stopped"
    fi
fi
echo "Filebeat Status: $FILEBEAT_STATUS"

# 6. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "test_id": "$TEST_ID",
    "indexer_response": $QUERY_RESULT,
    "filebeat_config": $(echo "$FILEBEAT_CONFIG" | jq -R -s '.'),
    "filebeat_status": "$FILEBEAT_STATUS",
    "timestamp": "$(date -Iseconds)",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"
echo "=== Export Complete ==="