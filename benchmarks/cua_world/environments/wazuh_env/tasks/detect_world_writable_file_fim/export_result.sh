#!/bin/bash
echo "=== Exporting detect_world_writable_file_fim results ==="

source /workspace/scripts/task_utils.sh

# Timestamp
TASK_END=$(date +%s)
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Configuration Files for Verification
echo "Extracting configuration files..."
docker cp "${WAZUH_MANAGER_CONTAINER}:/var/ossec/etc/ossec.conf" /tmp/ossec_export.conf
docker cp "${WAZUH_MANAGER_CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules_export.xml

# 3. ACTIVE VERIFICATION: Simulate the Attack
# We perform the action that the agent's rule is supposed to catch.
echo "Running active verification probe..."

TARGET_DIR="/opt/secure_configs"
PROBE_FILE="$TARGET_DIR/verifier_probe_$(date +%s).conf"

# Create a probe file inside the container (mounted via volume or directly created)
# Note: The container mounts /home/ga/wazuh/config... but usually /opt is inside container.
# We create it inside the container to ensure FIM sees it.
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "touch $PROBE_FILE && chmod 600 $PROBE_FILE"
echo "Created probe file: $PROBE_FILE"

# Wait for FIM to potentially register the new file (if realtime)
sleep 5

# Perform the "Attack": Make it world writable
echo "Simulating attack: chmod 777 $PROBE_FILE"
docker exec "${WAZUH_MANAGER_CONTAINER}" chmod 777 "$PROBE_FILE"

# Wait for Alert generation (Wazuh analysis delay)
echo "Waiting for alert generation (15s)..."
sleep 15

# 4. Check for Alert
# Look for rule 110001 firing on our probe file in alerts.json
echo "Checking alerts.json..."
ALERT_FOUND="false"
ALERT_JSON=""

# We search the last 1000 lines of alerts.json inside the container
ALERT_DATA=$(docker exec "${WAZUH_MANAGER_CONTAINER}" tail -n 1000 /var/ossec/logs/alerts/alerts.json)

# Python script to parse the alert log and find our specific event
# We look for: rule.id == "110001" AND syscheck.path == PROBE_FILE
PARSED_RESULT=$(echo "$ALERT_DATA" | python3 -c "
import sys, json
found = False
detail = {}
probe_file = '$PROBE_FILE'
for line in sys.stdin:
    try:
        log = json.loads(line)
        if log.get('rule', {}).get('id') == '110001':
            # Check if it matches our probe file
            if log.get('syscheck', {}).get('path') == probe_file:
                found = True
                detail = log
    except:
        pass
print(json.dumps({'found': found, 'detail': detail}))
")

ALERT_FOUND=$(echo "$PARSED_RESULT" | jq -r .found)
ALERT_DETAIL=$(echo "$PARSED_RESULT" | jq -r .detail)

echo "Alert found status: $ALERT_FOUND"

# 5. Check if App (Wazuh Manager) is running
APP_RUNNING=$(is_wazuh_manager_running && echo "true" || echo "false")

# 6. Read Config Content (for static analysis in verifier)
OSSEC_CONF_CONTENT=$(cat /tmp/ossec_export.conf | base64 -w 0)
RULES_XML_CONTENT=$(cat /tmp/local_rules_export.xml | base64 -w 0)

# 7. Create Result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "app_running": $APP_RUNNING,
    "alert_triggered": $ALERT_FOUND,
    "alert_detail": $ALERT_DETAIL,
    "ossec_conf_b64": "$OSSEC_CONF_CONTENT",
    "local_rules_b64": "$RULES_XML_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "=== Export complete ==="