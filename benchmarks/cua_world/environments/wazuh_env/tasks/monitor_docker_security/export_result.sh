#!/bin/bash
echo "=== Exporting monitor_docker_security results ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
NOW=$(date +%s)

# 1. Capture Final Screenshot
take_screenshot /tmp/task_final.png

# 2. Extract Configuration (ossec.conf)
# We need to check if docker-listener is enabled
docker cp "$CONTAINER":/var/ossec/etc/ossec.conf /tmp/ossec_export.conf 2>/dev/null || echo "Failed to copy ossec.conf" > /tmp/ossec_export.conf
OSSEC_CONF_CONTENT=$(cat /tmp/ossec_export.conf | base64 -w 0)

# 3. Extract Rules (local_rules.xml)
# We need to check for rule 100205
docker cp "$CONTAINER":/var/ossec/etc/rules/local_rules.xml /tmp/rules_export.xml 2>/dev/null || echo "Failed to copy local_rules.xml" > /tmp/rules_export.xml
RULES_CONTENT=$(cat /tmp/rules_export.xml | base64 -w 0)

# 4. Extract Alerts (alerts.json)
# We look for rule_id 100205 fired AFTER task start
# We'll filter inside the container to minimize data transfer, or copy the tail
# Let's copy the last 2000 lines, it should cover the session
docker exec "$CONTAINER" tail -n 2000 /var/ossec/logs/alerts/alerts.json > /tmp/alerts_tail.json 2>/dev/null || echo "" > /tmp/alerts_tail.json

# Process alerts to find hits for 100205
# We'll do this in python for robustness or simple grep here
HIT_COUNT=$(grep "\"rule\":{\"id\":\"100205\"" /tmp/alerts_tail.json | wc -l)
LAST_ALERT=$(grep "\"rule\":{\"id\":\"100205\"" /tmp/alerts_tail.json | tail -n 1 | base64 -w 0)

# 5. Check if module started (ossec.log)
docker exec "$CONTAINER" tail -n 1000 /var/ossec/logs/ossec.log > /tmp/ossec_log_tail.txt 2>/dev/null
LISTENER_STARTED=$(grep -i "wazuh-modulesd:docker-listener: INFO: Module started" /tmp/ossec_log_tail.txt | wc -l)

# 6. Check if image exists (did they run the tagging command?)
IMAGE_EXISTS=$(docker images | grep "crypto-miner" | wc -l)

# Create JSON Result
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $NOW,
    "ossec_conf_b64": "$OSSEC_CONF_CONTENT",
    "rules_xml_b64": "$RULES_CONTENT",
    "alert_hit_count": $HIT_COUNT,
    "last_alert_b64": "$LAST_ALERT",
    "listener_started_log_count": $LISTENER_STARTED,
    "image_tagged": $IMAGE_EXISTS,
    "screenshot_path": "/tmp/task_final.png"
}
EOF

# Move to final location
rm -f /tmp/task_result.json 2>/dev/null || sudo rm -f /tmp/task_result.json 2>/dev/null || true
cp "$TEMP_JSON" /tmp/task_result.json
chmod 666 /tmp/task_result.json
rm "$TEMP_JSON" /tmp/ossec_export.conf /tmp/rules_export.xml /tmp/alerts_tail.json /tmp/ossec_log_tail.txt

echo "Export complete. Result saved to /tmp/task_result.json"