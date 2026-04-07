#!/bin/bash
echo "=== Exporting task results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="${WAZUH_MANAGER_CONTAINER}"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TEST_LOG_FILE="/var/log/payment_app.log"

# 1. LIVE FIRE TEST
# We simulate the log entry to see if the alert actually triggers.
# This proves the config is functional, not just textually present.
echo "Running Live Fire Test..."

# Create the log file inside container if it doesn't exist
docker exec "$CONTAINER" touch "$TEST_LOG_FILE"
docker exec "$CONTAINER" chmod 666 "$TEST_LOG_FILE"

# Inject the trigger log
# We use a unique ID to identify this specific test run
TEST_ID="TEST-$(date +%s)"
TRIGGER_MSG="Nov 01 12:00:00 localhost payment_gateway: Transaction: VOID - ID: $TEST_ID"

echo "Injecting log: $TRIGGER_MSG"
docker exec "$CONTAINER" bash -c "echo '$TRIGGER_MSG' >> $TEST_LOG_FILE"

# Wait for Wazuh to process (usually takes 1-5 seconds)
sleep 10

# Check for the alert in alerts.json
# We look for the specific Test ID to ensure we don't catch old alerts
ALERT_FOUND="false"
ALERT_JSON=""

# Grep for the test ID in alerts.json
# Using docker exec to grep inside
ALERT_LINE=$(docker exec "$CONTAINER" grep "$TEST_ID" /var/ossec/logs/alerts/alerts.json | tail -n 1 || echo "")

if [ -n "$ALERT_LINE" ]; then
    echo "Alert found!"
    ALERT_FOUND="true"
    ALERT_JSON="$ALERT_LINE"
else
    echo "Alert NOT found for ID $TEST_ID"
fi

# 2. EXTRACT CONFIGURATIONS
# We read the files to verification JSON so python can parse them
OSSEC_CONF_CONTENT=$(docker exec "$CONTAINER" cat /var/ossec/etc/ossec.conf | base64 -w 0)
LOCAL_RULES_CONTENT=$(docker exec "$CONTAINER" cat /var/ossec/etc/rules/local_rules.xml | base64 -w 0)

# 3. CHECK PROCESS STATUS
APP_RUNNING=$(docker exec "$CONTAINER" ps aux | grep -q "ossec-analysisd" && echo "true" || echo "false")

# 4. TAKE FINAL SCREENSHOT
take_screenshot /tmp/task_final.png

# 5. COMPILE RESULT JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "app_running": $APP_RUNNING,
    "alert_triggered": $ALERT_FOUND,
    "alert_data": ${ALERT_JSON:-{}},
    "ossec_conf_b64": "$OSSEC_CONF_CONTENT",
    "local_rules_b64": "$LOCAL_RULES_CONTENT",
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to standard location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json 2>/dev/null || sudo cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json 2>/dev/null || sudo chmod 666 /tmp/task_result.json 2>/dev/null || true
rm -f "$TEMP_JSON"

echo "Result exported to /tmp/task_result.json"