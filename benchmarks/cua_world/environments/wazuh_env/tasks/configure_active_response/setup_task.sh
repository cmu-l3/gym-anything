#!/bin/bash
set -e
echo "=== Setting up configure_active_response task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh manager is running
if ! check_api_health; then
    echo "Waiting for Wazuh API to become available..."
    sleep 10
    if ! check_api_health; then
        echo "Restarting Wazuh manager container..."
        docker restart "${WAZUH_MANAGER_CONTAINER}"
        sleep 30
    fi
fi

# PREPARE CLEAN STATE: Remove any existing firewall-drop command or active-response from ossec.conf
# We want the agent to do this from scratch.
echo "Preparing clean ossec.conf..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak"

# Use python inside container (if available) or sed to strip existing blocks
# We'll use a sed strategy to remove specific blocks if they exist to ensure idempotency
# Removing <command> block for firewall-drop
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<command>/,/<\\/command>/ { /<name>firewall-drop<\\/name>/d; }' /var/ossec/etc/ossec.conf"
# Removing <active-response> block for firewall-drop
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<active-response>/,/<\\/active-response>/ { /<command>firewall-drop<\\/command>/d; }' /var/ossec/etc/ossec.conf"

# Remove empty XML tags left by sed if any (simple cleanup)
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<command>\s*<\/command>/d' /var/ossec/etc/ossec.conf"
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<active-response>\s*<\/active-response>/d' /var/ossec/etc/ossec.conf"

# Restart manager to apply clean state (so API doesn't show them)
echo "Applying clean state..."
restart_wazuh_manager > /dev/null 2>&1

# Record initial file stats
INITIAL_MTIME=$(docker exec "${WAZUH_MANAGER_CONTAINER}" stat -c %Y /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_ossec_mtime.txt

# Open Wazuh Dashboard
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_URL_CONFIG}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="