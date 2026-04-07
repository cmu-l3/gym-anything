#!/bin/bash
set -e
echo "=== Setting up Asset Inventory Task ==="

source /workspace/scripts/task_utils.sh

# 1. Record Start Time (Anti-gaming)
date +%s > /tmp/task_start_time.txt

# 2. Ensure Nx Server is running
echo "Checking Nx Witness Server status..."
if ! systemctl is-active --quiet networkoptix-mediaserver; then
    systemctl start networkoptix-mediaserver
    sleep 5
fi

# 3. Ensure we have valid auth to verify system is ready
# This also warms up the API
echo "Validating API access..."
TOKEN=$(refresh_nx_token)
if [ -z "$TOKEN" ]; then
    echo "ERROR: Failed to obtain API token during setup."
    exit 1
fi

# 4. Clean up previous run artifacts
rm -f /home/ga/Documents/system_inventory.json
rm -rf /tmp/ground_truth
mkdir -p /home/ga/Documents
chown ga:ga /home/ga/Documents

# 5. Open Firefox to Web Admin (Documentation reference for agent)
# The agent might use the web admin to explore the API documentation or view IDs
echo "Launching Firefox..."
ensure_firefox_running "https://localhost:7001/static/index.html#/settings/system"
maximize_firefox

# 6. Take initial screenshot
echo "Capturing initial state..."
sleep 2
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Target: Generate /home/ga/Documents/system_inventory.json"
echo "API: https://localhost:7001"