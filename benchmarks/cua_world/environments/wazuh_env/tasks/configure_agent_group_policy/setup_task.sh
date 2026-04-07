#!/bin/bash
# pre_task: Setup for configure_agent_group_policy
echo "=== Setting up configure_agent_group_policy task ==="

source /workspace/scripts/task_utils.sh

GROUP_ID="linux-webservers"
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Clean up: Ensure group does not exist
echo "Checking if group '$GROUP_ID' exists..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    # Check via API
    HTTP_CODE=$(curl -sk -o /dev/null -w "%{http_code}" -X GET "${WAZUH_API_URL}/groups/${GROUP_ID}" \
        -H "Authorization: Bearer ${TOKEN}")
    
    if [ "$HTTP_CODE" == "200" ]; then
        echo "Group exists. Removing..."
        curl -sk -X DELETE "${WAZUH_API_URL}/groups?groups_list=${GROUP_ID}" \
            -H "Authorization: Bearer ${TOKEN}"
        sleep 2
    fi
fi

# Double check via filesystem in container
echo "Cleaning up container filesystem..."
docker exec "${CONTAINER}" rm -rf "/var/ossec/etc/shared/${GROUP_ID}" 2>/dev/null || true

# 2. Record initial state
# Count total groups
INITIAL_GROUP_COUNT=$(wazuh_api GET "/groups?pretty=true" | grep -c "\"name\":" || echo "0")
echo "$INITIAL_GROUP_COUNT" > /tmp/initial_group_count.txt

# Record task start time
date +%s > /tmp/task_start_time.txt

# 3. Ensure Environment is ready
# Ensure Firefox is open (as per Starting State description)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="