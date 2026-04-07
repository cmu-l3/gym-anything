#!/bin/bash
set -e
echo "=== Setting up Bulk Agent Cleanup Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh manager is running
if ! docker ps | grep -q "${WAZUH_MANAGER_CONTAINER}"; then
    echo "Starting Wazuh manager container..."
    docker start "${WAZUH_MANAGER_CONTAINER}"
    sleep 15
fi

# Wait for API to be ready
echo "Waiting for Wazuh API..."
wait_for_service "Wazuh API" "curl -sk -u ${WAZUH_API_USER}:${WAZUH_API_PASS} ${WAZUH_API_URL}/" 60

# --- Clean Slate: Remove ALL agents except 000 ---
echo "Cleaning existing agents..."
# Get list of agent IDs to remove (ID > 0)
AGENTS_TO_REMOVE=$(wazuh_api GET "/agents?limit=500" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
# Filter out ID 000
ids = [a['id'] for a in items if a['id'] != '000']
print(' '.join(ids))
" 2>/dev/null || true)

if [ -n "$AGENTS_TO_REMOVE" ]; then
    echo "Removing agents: $AGENTS_TO_REMOVE"
    # Use manage_agents inside container for forceful removal (faster than API loop for setup)
    for id in $AGENTS_TO_REMOVE; do
        docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/manage_agents -r "$id" >/dev/null 2>&1 || true
    done
fi

# Restart manager to flush state if needed, but managing agents usually updates immediately.
# We'll just force a restart at the end of setup to be clean.

# --- Register Production Agents ---
echo "Registering production agents..."
docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/manage_agents -a "192.168.1.10" -n "production-web" >/dev/null
docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/manage_agents -a "192.168.1.11" -n "production-db" >/dev/null

# --- Register Stale Agents (Batch) ---
echo "Registering stale agents..."
for i in {01..25}; do
    # Registering 25 agents
    IP_SUFFIX=$((20 + 10#$i)) # IPs 192.168.1.21 ...
    NAME="temp-test-${i}"
    echo "  Adding $NAME..."
    docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/manage_agents -a "192.168.1.${IP_SUFFIX}" -n "$NAME" >/dev/null
done

# Restart manager to ensure all agents appear properly in dashboard
echo "Restarting Wazuh manager to apply changes..."
restart_wazuh_manager

# Wait for API again
wait_for_service "Wazuh API" "curl -sk -u ${WAZUH_API_USER}:${WAZUH_API_PASS} ${WAZUH_API_URL}/" 120

# Record initial count
INITIAL_COUNT=$(get_agent_count)
echo "Initial agent count: $INITIAL_COUNT"
echo "$INITIAL_COUNT" > /tmp/initial_agent_count.txt

# Open Dashboard to Agents list to show the mess
echo "Opening Dashboard..."
ensure_firefox_wazuh "${WAZUH_URL_AGENTS}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="
echo "Total agents: $INITIAL_COUNT"
echo "Production agents: production-web, production-db"
echo "Stale agents: temp-test-01 through temp-test-25"