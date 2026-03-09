#!/bin/bash
# setup_task.sh — Prepare environment for system health report task
set -e

source /workspace/scripts/task_utils.sh

echo "=== Setting up system health report task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Wait for Emoncms to be fully operational
wait_for_emoncms
sleep 5

# -----------------------------------------------------------------------
# Capture ground truth values for verification (Hidden from agent)
# -----------------------------------------------------------------------
echo "Capturing ground truth system state..."
APIKEY=$(get_apikey_write)

# 1. Feed count via API
FEED_LIST=$(curl -s "${EMONCMS_URL}/feed/list.json?apikey=${APIKEY}" 2>/dev/null || echo "[]")
FEED_COUNT=$(echo "$FEED_LIST" | python3 -c "import sys, json; print(len(json.load(sys.stdin)))" 2>/dev/null || echo "0")

# 2. Input count via API (robust parsing for list vs dict)
INPUT_LIST=$(curl -s "${EMONCMS_URL}/input/list.json?apikey=${APIKEY}" 2>/dev/null || echo "[]")
INPUT_COUNT=$(echo "$INPUT_LIST" | python3 -c "
import sys, json
try:
    data = json.load(sys.stdin)
    if isinstance(data, list):
        print(len(data))
    elif isinstance(data, dict):
        count = 0
        for node_inputs in data.values():
            if isinstance(node_inputs, (list, dict)):
                count += len(node_inputs)
            else:
                count += 1
        print(count)
    else:
        print(0)
except:
    print(0)
" 2>/dev/null || echo "0")

# 3. MySQL version
MYSQL_VER_FULL=$(docker exec emoncms-db mysql -V 2>/dev/null || echo "unknown")
MYSQL_VER=$(echo "$MYSQL_VER_FULL" | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")

# 4. PHP version
PHP_VER_FULL=$(docker exec emoncms-web php -v 2>/dev/null | head -1 || echo "unknown")
PHP_VER=$(echo "$PHP_VER_FULL" | grep -oP '[\d]+\.[\d]+\.[\d]+' | head -1 || echo "unknown")

# 5. Redis status
REDIS_PING=$(docker exec emoncms-redis redis-cli ping 2>/dev/null || echo "FAIL")
if [ "$REDIS_PING" = "PONG" ]; then
    REDIS_STATUS="Connected"
else
    REDIS_STATUS="Disconnected"
fi

# 6. MQTT status (Derived from settings.ini or assumed disabled in this env)
# In this environment, settings.ini usually has mqtt enabled=false
MQTT_STATUS="Disabled"
if docker exec emoncms-web grep -q "mqtt.*enabled.*=.*true" /var/www/emoncms/settings.ini 2>/dev/null; then
    MQTT_STATUS="Connected" # Assuming if enabled it tries to connect
fi

# 7. Emoncms version
# Try to read version.txt
EMONCMS_VER=$(docker exec emoncms-web cat /var/www/emoncms/version.txt 2>/dev/null || echo "unknown")
if [ "$EMONCMS_VER" = "unknown" ]; then
     # Fallback to API info
     ADMIN_INFO=$(curl -s "${EMONCMS_URL}/admin/info.json?apikey=${APIKEY}" 2>/dev/null || echo "{}")
     EMONCMS_VER=$(echo "$ADMIN_INFO" | python3 -c "import sys, json; print(json.load(sys.stdin).get('emoncms_version', 'unknown'))" 2>/dev/null)
fi

# Save Ground Truth to a JSON file (root owned, readable by verifier later)
cat > /tmp/ground_truth.json << EOF
{
    "feed_count": $FEED_COUNT,
    "input_count": $INPUT_COUNT,
    "mysql_version": "$MYSQL_VER",
    "php_version": "$PHP_VER",
    "redis_status": "$REDIS_STATUS",
    "mqtt_status": "$MQTT_STATUS",
    "emoncms_version": "$EMONCMS_VER"
}
EOF
chmod 644 /tmp/ground_truth.json

echo "Ground Truth captured:"
cat /tmp/ground_truth.json

# -----------------------------------------------------------------------
# Clean up any pre-existing report
# -----------------------------------------------------------------------
rm -f /home/ga/system_health_report.txt

# -----------------------------------------------------------------------
# Launch Firefox to Emoncms main page (logged in)
# -----------------------------------------------------------------------
launch_firefox_to "http://localhost/" 8

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="