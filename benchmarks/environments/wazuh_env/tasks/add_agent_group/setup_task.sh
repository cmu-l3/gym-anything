#!/bin/bash
# pre_task: Setup for add_agent_group task
echo "=== Setting up add_agent_group task ==="

source /workspace/scripts/task_utils.sh

# Remove the target group if it already exists (ensure clean state)
echo "Cleaning up any existing 'dmz-servers' group..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    # Check if group exists
    GROUPS=$(curl -sk -X GET "${WAZUH_API_URL}/groups?search=dmz-servers" \
        -H "Authorization: Bearer ${TOKEN}")

    # If group exists, remove it
    if echo "$GROUPS" | grep -q '"dmz-servers"'; then
        echo "Group 'dmz-servers' exists, removing it for clean task setup..."
        curl -sk -X DELETE "${WAZUH_API_URL}/groups?groups_list=dmz-servers" \
            -H "Authorization: Bearer ${TOKEN}" > /dev/null 2>&1 || true
    fi
fi

# Verify existing groups are present (linux-servers, windows-workstations, etc.)
echo "Existing groups:"
wazuh_api GET "/groups" | python3 -c "
import sys, json
data = json.load(sys.stdin)
groups = data.get('data', {}).get('affected_items', [])
for g in groups:
    print(f\"  - {g.get('name', 'unknown')} ({g.get('count', 0)} agents)\")
" 2>/dev/null || echo "  (could not parse groups)"

# Ensure Firefox is showing the Wazuh dashboard
echo "Ensuring Firefox is open on Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3

# Navigate to the Groups management page
navigate_firefox_to "${WAZUH_URL_GROUPS}"
sleep 5

take_screenshot /tmp/add_agent_group_initial.png
echo "Initial screenshot saved to /tmp/add_agent_group_initial.png"

echo "=== add_agent_group task setup complete ==="
echo "Task: Create a new agent group named 'dmz-servers'"
echo "Navigate to: Management > Groups > Add new group"
