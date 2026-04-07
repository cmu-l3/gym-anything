#!/bin/bash
# Export results for implement_custom_app_brute_force
# This script performs a LIVE FIRE verification of the agent's work.

echo "=== Exporting Task Results ==="
source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
LOG_FILE="/var/log/finconnect/app.log"
VERIFIER_IP="10.254.254.254"
VERIFIER_USER="verifier_bot"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Export Configuration Files (for static analysis)
echo "Exporting configuration files..."
docker cp "$CONTAINER:/var/ossec/etc/ossec.conf" /tmp/ossec_final.conf
docker cp "$CONTAINER:/var/ossec/etc/decoders/local_decoder.xml" /tmp/decoder_final.xml
docker cp "$CONTAINER:/var/ossec/etc/rules/local_rules.xml" /tmp/rules_final.xml
docker cp "$CONTAINER:/var/ossec/logs/alerts/alerts.json" /tmp/alerts_full.json

# 2. Check if Manager is Running
MANAGER_RUNNING="false"
if docker exec "$CONTAINER" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# 3. LIVE FIRE TEST
# We inject a specific attack pattern to see if the system detects IT (not just the agent's tests).
VERIFICATION_TRIGGERED="false"
VERIFICATION_ALERT_DATA="{}"

if [ "$MANAGER_RUNNING" = "true" ]; then
    echo "Starting Live Fire Verification..."
    
    # Inject 6 failed logins within ~2 seconds (exceeds 5 in 30s)
    # Using the exact format specified in the task
    for i in {1..6}; do
        TS=$(date "+%Y-%m-%d %H:%M:%S")
        LOG_LINE="$TS FinConnect: [Login] User=$VERIFIER_USER IP=$VERIFIER_IP Status=Failed"
        docker exec "$CONTAINER" bash -c "echo '$LOG_LINE' >> $LOG_FILE"
        sleep 0.2
    done
    
    echo "Attack logs injected. Waiting 15s for processing..."
    sleep 15
    
    # Check alerts.json for our specific verifier IP and Rule 100210
    # We look for the MOST RECENT alert matching our criteria
    ALERT_JSON=$(docker exec "$CONTAINER" grep "$VERIFIER_IP" /var/ossec/logs/alerts/alerts.json | \
                 grep "\"id\":\"100210\"" | tail -n 1)
                 
    if [ -n "$ALERT_JSON" ]; then
        VERIFICATION_TRIGGERED="true"
        VERIFICATION_ALERT_DATA="$ALERT_JSON"
        echo "VERIFICATION SUCCESS: Detected verifier attack!"
    else
        echo "VERIFICATION FAILED: Did not detect verifier attack."
        # Debug: Check if base rule fired
        BASE_ALERTS=$(docker exec "$CONTAINER" grep "$VERIFIER_IP" /var/ossec/logs/alerts/alerts.json | grep "\"id\":\"100205\"" | wc -l)
        echo "Debug: Found $BASE_ALERTS base rule (100205) triggers for verifier IP."
    fi
else
    echo "Manager not running, skipping live fire test."
fi

# 4. Agent's Own Testing Evidence
# Check if there are ANY alerts for rule 100210 that occurred after task start
# (excluding our verification run if possible, or just counting total)
AGENT_TEST_COUNT=$(docker exec "$CONTAINER" grep "\"id\":\"100210\"" /var/ossec/logs/alerts/alerts.json | wc -l)

# 5. Final Screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "manager_running": $MANAGER_RUNNING,
    "verification_triggered": $VERIFICATION_TRIGGERED,
    "verification_alert": $VERIFICATION_ALERT_DATA,
    "total_brute_force_alerts": $AGENT_TEST_COUNT,
    "ossec_conf_path": "/tmp/ossec_final.conf",
    "decoder_xml_path": "/tmp/decoder_final.xml",
    "rules_xml_path": "/tmp/rules_final.xml",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Safe move
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

# Display result for log
cat /tmp/task_result.json
echo "=== Export Complete ==="