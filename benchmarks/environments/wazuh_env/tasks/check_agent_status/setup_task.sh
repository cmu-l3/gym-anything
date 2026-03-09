#!/bin/bash
# pre_task: Setup for check_agent_status task
echo "=== Setting up check_agent_status task ==="

source /workspace/scripts/task_utils.sh

# Log current agent status via API for reference
echo "Current agent status:"
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    AGENTS=$(curl -sk -X GET "${WAZUH_API_URL}/agents?select=id,name,status,ip,os.name,version,lastKeepAlive" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    echo "$AGENTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
for a in items:
    status = a.get('status', 'unknown')
    name = a.get('name', 'unknown')
    agent_id = a.get('id', 'unknown')
    version = a.get('version', 'unknown')
    print(f\"  Agent {agent_id}: {name} - Status: {status} - Version: {version}\")
" 2>/dev/null || echo "  (could not parse agents)"
fi

# Open Firefox on the Agents page showing the agents list
echo "Opening Configuration Assessment (SCA) page for agent 000..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3

navigate_firefox_to "${WAZUH_URL_SCA}"
sleep 6

take_screenshot /tmp/check_agent_status_initial.png
echo "Initial screenshot saved to /tmp/check_agent_status_initial.png"

echo "=== check_agent_status task setup complete ==="
echo "Task: View CIS Benchmark SCA checks, click a failed check to see its detail"
echo "Current page: Configuration Assessment overview showing compliance score"
echo "Next step: Click Checks tab, then click any failed check to expand details"
