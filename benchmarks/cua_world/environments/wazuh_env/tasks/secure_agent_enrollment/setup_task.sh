#!/bin/bash
set -e
echo "=== Setting up secure_agent_enrollment task ==="

source /workspace/scripts/task_utils.sh

# Container name
CONTAINER="wazuh-wazuh.manager-1"

# 1. Ensure Wazuh Manager is running
echo "Checking Wazuh Manager container status..."
if ! docker ps | grep -q "$CONTAINER"; then
    echo "Starting Wazuh Manager container..."
    docker start "$CONTAINER"
    sleep 10
fi

# 2. Reset state: Remove authd.pass if it exists
echo "Cleaning up previous password file..."
docker exec "$CONTAINER" rm -f /var/ossec/etc/authd.pass 2>/dev/null || true

# 3. Reset state: Revert ossec.conf auth section to defaults
# We use sed to ensure defaults: use_password=no, force_insert=no
echo "Resetting ossec.conf auth settings..."
docker exec "$CONTAINER" sed -i 's|<use_password>yes</use_password>|<use_password>no</use_password>|g' /var/ossec/etc/ossec.conf
docker exec "$CONTAINER" sed -i 's|<force_insert>yes</force_insert>|<force_insert>no</force_insert>|g' /var/ossec/etc/ossec.conf

# 4. Restart manager to ensure clean state
echo "Restarting Wazuh Manager..."
docker exec "$CONTAINER" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1
sleep 5

# 5. Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 6. Take initial screenshot
# We'll show the terminal or dashboard
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="