#!/bin/bash
set -e
echo "=== Setting up automate_asset_inventory_export task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# 1. Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Install Python dependencies (requests) to ensure agent can write the script easily
echo "Installing python requests library..."
if ! python3 -c "import requests" 2>/dev/null; then
    apt-get update && apt-get install -y python3-requests || pip3 install requests
fi

# 3. Clean up previous artifacts
rm -f /home/ga/agent_reporter.py
rm -f /home/ga/active_agents.csv
rm -f /tmp/verification_run.csv
rm -f /tmp/script_execution.log

# 4. Ensure Wazuh API is up and reachable
echo "Waiting for Wazuh API to be ready..."
for i in {1..30}; do
    if curl -sk -u "${WAZUH_API_USER}:${WAZUH_API_PASS}" "${WAZUH_API_URL}/" >/dev/null; then
        echo "Wazuh API is ready."
        break
    fi
    sleep 2
done

# 5. Capture initial state (List of active agents for ground truth)
echo "Capturing ground truth active agents..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    curl -sk -X GET "${WAZUH_API_URL}/agents?status=active&select=id,name" \
        -H "Authorization: Bearer ${TOKEN}" > /tmp/initial_active_agents.json
else
    echo "WARNING: Could not get API token for ground truth setup."
    echo "{}" > /tmp/initial_active_agents.json
fi

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="