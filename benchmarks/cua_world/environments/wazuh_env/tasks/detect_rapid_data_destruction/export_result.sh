#!/bin/bash
echo "=== Exporting Detect Rapid Data Destruction results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TARGET_DIR="/var/ossec/data/financial_records"
TASK_START_TIME=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Check if Manager is running
MANAGER_RUNNING="false"
if docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi
echo "Manager running: $MANAGER_RUNNING"

# 3. FUNCTIONAL SIMULATION (The "Attack")
# We simulate the rapid deletion of files to see if the rule triggers.
# This must happen inside the container environment.
ALERT_TRIGGERED="false"
SIMULATION_ATTEMPTED="false"

if [ "$MANAGER_RUNNING" = "true" ]; then
    echo "Simulating ransomware behavior (rapid deletion)..."
    SIMULATION_ATTEMPTED="true"
    
    # Wait a moment to ensure FIM syscheck has picked up the files (if restart just happened)
    # Force a syscheck scan if possible, or wait for realtime
    # Realtime usually picks up immediately if configured correctly.
    sleep 5

    # Delete 6 files (threshold is 5)
    docker exec "${CONTAINER}" bash -c "rm -f $TARGET_DIR/invoice_{1..6}.pdf"
    
    # Wait for analysisd to process events (FIM -> Alert -> Correlation)
    echo "Waiting for alert generation (up to 20s)..."
    sleep 20

    # Check alerts.json for the specific rule ID *after* the task started
    # We look for the rule ID 100250
    if docker exec "${CONTAINER}" grep "\"rule\":{\"id\":\"100250\"" /var/ossec/logs/alerts/alerts.json | tail -n 5 | grep -q "invoice_"; then
        ALERT_TRIGGERED="true"
        echo "SUCCESS: Rule 100250 triggered during simulation."
    else
        echo "FAILURE: Rule 100250 did NOT trigger during simulation."
        # Debug: check if standard deletion fired (rule 553)
        echo "Checking if basic file deletion (553) fired..."
        docker exec "${CONTAINER}" grep "\"rule\":{\"id\":\"553\"" /var/ossec/logs/alerts/alerts.json | tail -n 5 || echo "No rule 553 alerts found recently"
    fi
else
    echo "Skipping simulation because manager is not running."
fi

# 4. Export Configuration Files for Static Analysis
echo "Exporting configuration files..."

# Export ossec.conf
docker cp "${CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec.conf.export
OSSEC_CONF_CONTENT=$(cat /tmp/ossec.conf.export | base64 -w 0)

# Export local_rules.xml
docker cp "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules.xml.export
LOCAL_RULES_CONTENT=$(cat /tmp/local_rules.xml.export | base64 -w 0)

# Clean up exported files
rm -f /tmp/ossec.conf.export /tmp/local_rules.xml.export

# 5. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start_time": $TASK_START_TIME,
    "manager_running": $MANAGER_RUNNING,
    "simulation_attempted": $SIMULATION_ATTEMPTED,
    "alert_triggered": $ALERT_TRIGGERED,
    "ossec_conf_b64": "$OSSEC_CONF_CONTENT",
    "local_rules_b64": "$LOCAL_RULES_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard result location
mv "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json

echo "Result exported to /tmp/task_result.json"
echo "=== Export complete ==="