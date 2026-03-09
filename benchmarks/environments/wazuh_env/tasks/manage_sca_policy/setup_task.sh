#!/bin/bash
# pre_task: Setup for manage_sca_policy task
echo "=== Setting up manage_sca_policy task ==="

source /workspace/scripts/task_utils.sh

# Check if SCA is enabled on agent 000
echo "Checking SCA configuration..."
docker exec "${WAZUH_MANAGER_CONTAINER}" grep -A3 "<sca>" /var/ossec/etc/ossec.conf 2>/dev/null || echo "SCA config not found (may be in default)"

# Wait for any pending SCA scans
echo "Waiting for SCA data to be available..."
sleep 5

# Verify SCA data via API
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    SCA_RESULT=$(curl -sk -X GET "${WAZUH_API_URL}/sca/000" \
        -H "Authorization: Bearer ${TOKEN}" 2>/dev/null)
    echo "SCA policies for agent 000:"
    echo "$SCA_RESULT" | python3 -c "
import sys, json
data = json.load(sys.stdin)
items = data.get('data', {}).get('affected_items', [])
for p in items:
    print(f\"  Policy: {p.get('name', 'unknown')} - Pass: {p.get('pass', 0)}, Fail: {p.get('fail', 0)}, Score: {p.get('score', 0)}%\")
if not items:
    print('  (No SCA data yet - first scan may still be running)')
" 2>/dev/null || echo "  (could not parse SCA data)"
fi

# Navigate to agent 000 detail page (SCA tab is visible from there)
echo "Opening agent 000 page..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 3

navigate_firefox_to "${WAZUH_URL_SCA}"
sleep 6

take_screenshot /tmp/manage_sca_policy_initial.png
echo "Initial screenshot saved to /tmp/manage_sca_policy_initial.png"

echo "=== manage_sca_policy task setup complete ==="
echo "Task: View SCA policy results for agent 000 (Wazuh manager)"
echo "Current page: Agent 000 detail view"
echo "Next step: Click 'SCA' tab to see Security Configuration Assessment results"
