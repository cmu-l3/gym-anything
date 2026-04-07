#!/bin/bash
echo "=== Exporting configure_remote_syslog_ingestion result ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TIMESTAMP=$(date -Iseconds)

# --- 1. Inspect Configuration Files ---

# Read ossec.conf
echo "Reading ossec.conf..."
OSSEC_CONF=$(docker exec "${CONTAINER}" cat /var/ossec/etc/ossec.conf)

# Read local_rules.xml
echo "Reading local_rules.xml..."
LOCAL_RULES=$(docker exec "${CONTAINER}" cat /var/ossec/etc/rules/local_rules.xml)

# --- 2. Check Port Status ---

echo "Checking listening ports..."
# Check inside container
NETSTAT_OUTPUT=$(docker exec "${CONTAINER}" netstat -ulnp 2>/dev/null || echo "")
IS_LISTENING_514=$(echo "$NETSTAT_OUTPUT" | grep ":514 " | grep -q "ossec-remoted" && echo "true" || echo "false")

# --- 3. Functional Test (Log Injection) ---

ALERT_GENERATED="false"
ALERT_DATA="{}"

if [ "$IS_LISTENING_514" = "true" ]; then
    echo "Port 514 is open. Attempting log injection..."
    
    # Test Log Message matching the requirement
    TEST_LOG="<134>Mar 15 10:00:00 cisco-asa %ASA-4-106023: Deny tcp src outside:198.51.100.1/443 dst inside:10.0.0.5/80"
    
    # Send via nc to localhost:514 (mapped to container)
    # Using -u for UDP, -w 1 for timeout
    echo "$TEST_LOG" | nc -u -w 1 127.0.0.1 514
    
    echo "Log injected. Waiting for processing..."
    sleep 10
    
    # Query API for recent alerts
    echo "Querying API for alerts..."
    TOKEN=$(get_api_token)
    
    # Look for rule 100100 fired in last 5 minutes
    # Using 'rule.id' filter
    API_RESPONSE=$(curl -sk -X GET "${WAZUH_API_URL}/alerts?rule_ids=100100&time_range=5m" \
        -H "Authorization: Bearer ${TOKEN}")
        
    TOTAL_ALERTS=$(echo "$API_RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin).get('data', {}).get('total_affected_items', 0))" 2>/dev/null || echo "0")
    
    if [ "$TOTAL_ALERTS" -gt "0" ]; then
        ALERT_GENERATED="true"
        # Extract first alert for details
        ALERT_DATA=$(echo "$API_RESPONSE" | python3 -c "import sys, json; print(json.dumps(json.load(sys.stdin).get('data', {}).get('affected_items', [{}])[0]))" 2>/dev/null || echo "{}")
        echo "Alert detected!"
    else
        echo "No alerts found for rule 100100."
    fi
fi

# --- 4. Final Screenshot ---
take_screenshot /tmp/task_final.png

# --- 5. Save Result JSON ---

TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "timestamp": "$TIMESTAMP",
    "ossec_conf_content": $(echo "$OSSEC_CONF" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "local_rules_content": $(echo "$LOCAL_RULES" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "netstat_output": $(echo "$NETSTAT_OUTPUT" | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read()))'),
    "is_listening_514": $IS_LISTENING_514,
    "alert_generated": $ALERT_GENERATED,
    "alert_data": $ALERT_DATA,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location safely
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm -f "$TEMP_JSON"

echo "Result saved to /tmp/task_result.json"
cat /tmp/task_result.json
echo "=== Export complete ==="