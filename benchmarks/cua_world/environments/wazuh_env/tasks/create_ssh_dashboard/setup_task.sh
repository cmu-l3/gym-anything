#!/bin/bash
set -e
echo "=== Setting up SSH Dashboard Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh services are running
if ! check_indexer_health; then
    echo "Waiting for Wazuh Indexer..."
    sleep 30
fi

# 1. Inject Synthetic Data
# We inject data BEFORE the user starts so they have something to visualize immediately.
# We use 'logger' inside the manager container to simulate SSH auth failures.
echo "Injecting synthetic SSH failure logs..."
CONTAINER="${WAZUH_MANAGER_CONTAINER}"
LOG_CMD="logger -t sshd"

# IPs and Users for variety
IPS=("192.168.1.50" "10.0.0.5" "172.16.0.23" "45.33.12.9" "185.20.1.4" "203.0.113.88" "198.51.100.2")
USERS=("root" "admin" "ubuntu" "test" "oracle" "postgres" "guest")

# Generate ~50 logs
for i in {1..50}; do
    # Pick random IP and User
    IP=${IPS[$((RANDOM % ${#IPS[@]}))]}
    USER=${USERS[$((RANDOM % ${#USERS[@]}))]}
    
    # Log format that triggers standard SSH rules (e.g., Rule 5716)
    # "Failed password for invalid user <user> from <ip> port <port> ssh2"
    docker exec "$CONTAINER" $LOG_CMD "Failed password for invalid user $USER from $IP port 55$i ssh2"
    
    # Slight delay to ensure order (though mostly minimal)
    # We don't sleep too long to keep setup fast
    if (( i % 10 == 0 )); then sleep 1; fi
done
echo "Data injection complete."

# 2. Open Firefox to Wazuh Dashboard
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Navigate to Visualize or Discover to give a hint? 
# Better to start at Home so they have to navigate.
navigate_firefox_to "${WAZUH_URL_HOME}"
sleep 5

# 3. Capture Initial State
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="