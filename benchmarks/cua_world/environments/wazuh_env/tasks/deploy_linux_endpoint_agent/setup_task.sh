#!/bin/bash
set -e
echo "=== Setting up deploy_linux_endpoint_agent task ==="

# Load utils
source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh Manager is running and healthy
echo "Checking Wazuh Manager health..."
if ! check_api_health; then
    echo "Wazuh Manager API not reachable. Restarting manager..."
    restart_wazuh_manager
    # Wait for API to come up
    for i in {1..30}; do
        if check_api_health; then
            echo "Manager is ready."
            break
        fi
        sleep 5
    done
fi

# CLEANUP: Remove any existing Wazuh Agent installation on the host
# This ensures the agent must perform the installation
if dpkg -l | grep -q wazuh-agent; then
    echo "Removing existing wazuh-agent..."
    systemctl stop wazuh-agent 2>/dev/null || true
    apt-get remove -y --purge wazuh-agent
    rm -rf /var/ossec/etc 2>/dev/null || true
    rm -rf /var/ossec/logs 2>/dev/null || true
fi

# Remove agent from Manager if it exists (to force re-enrollment)
TOKEN=$(get_api_token)
AGENT_ID=$(wazuh_api GET "/agents?search=production-db-01" | grep '"id":' | head -1 | awk -F'"' '{print $4}')

if [ -n "$AGENT_ID" ]; then
    echo "Removing old agent registration (ID: $AGENT_ID)..."
    curl -sk -X DELETE "${WAZUH_API_URL}/agents?agents_list=${AGENT_ID}" \
        -H "Authorization: Bearer ${TOKEN}"
fi

# Remove repository list if exists (force user to add it)
rm -f /etc/apt/sources.list.d/wazuh.list

# Update apt cache to ensure clean state
apt-get clean

# Take initial screenshot
take_screenshot /tmp/deploy_agent_initial.png

echo "=== Task setup complete ==="
echo "Goal: Install wazuh-agent, configure it for manager 127.0.0.1, name it 'production-db-01', and ensure it is Active."