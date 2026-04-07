#!/bin/bash
set -e
echo "=== Setting up configure_fim_syscheck task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh stack is running
if ! docker ps | grep -q "wazuh.manager"; then
    echo "Starting Wazuh stack..."
    cd /home/ga/wazuh
    docker compose up -d
    sleep 30
fi

# Wait for API to be ready
wait_for_service "Wazuh Manager API" "curl -sk -u '${WAZUH_API_USER}:${WAZUH_API_PASS}' ${WAZUH_API_URL}/ | grep -q Wazuh" 120

# CONTAINER NAME
CONTAINER="wazuh-wazuh.manager-1"

# Record initial ossec.conf hash for anti-gaming
if docker exec "$CONTAINER" [ -f /var/ossec/etc/ossec.conf ]; then
    INITIAL_HASH=$(docker exec "$CONTAINER" md5sum /var/ossec/etc/ossec.conf | awk '{print $1}')
    echo "$INITIAL_HASH" > /tmp/initial_ossec_hash.txt
    echo "Initial ossec.conf hash: $INITIAL_HASH"
else
    echo "ERROR: ossec.conf not found in container"
    exit 1
fi

# Reset ossec.conf to a known clean state (optional but good for consistency)
# We won't wipe it completely to avoid breaking the system, but we ensure
# it doesn't already have the target config to prevent false positives.
# (Skipping complex reset to avoid instability, relying on hash check)

# Ensure Firefox is open to Wazuh dashboard
# This provides context for the user, even if the task is terminal-heavy
ensure_firefox_wazuh "${WAZUH_URL_CONFIG}"

# Take screenshot of initial state
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="