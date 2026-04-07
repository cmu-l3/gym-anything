#!/bin/bash
echo "=== Setting up implement_ar_alert_forwarder task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

CONTAINER="wazuh-wazuh.manager-1"
SCRIPT_PATH="/var/ossec/active-response/bin/ticket_forwarder.py"
OUTPUT_PATH="/var/ossec/logs/ticketing_queue.json"

# Ensure Wazuh manager is running
echo "Checking Wazuh manager status..."
if ! docker ps | grep -q "$CONTAINER"; then
    echo "Starting Wazuh manager container..."
    docker start "$CONTAINER"
    sleep 10
fi

# Clean up previous attempts
echo "Cleaning up previous task artifacts..."
docker exec "$CONTAINER" rm -f "$SCRIPT_PATH" "$OUTPUT_PATH"

# Ensure clean state in ossec.conf (remove our specific blocks if they exist)
# We use a simple sed to try and remove lines if they were added previously, 
# but for safety we mostly rely on the agent managing the config.
# A backup restore would be better but complex in this env.
# We'll just create a backup of the current config to diff against later if needed.
docker exec "$CONTAINER" cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak_task_start

# Ensure Firefox is open and ready
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="