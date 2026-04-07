#!/bin/bash
echo "=== Exporting deploy_linux_endpoint_agent results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
TASK_END=$(date +%s)

# 1. Check Local Installation Status
PACKAGE_INSTALLED="false"
if dpkg -l | grep -q "wazuh-agent"; then
    PACKAGE_INSTALLED="true"
fi

SERVICE_RUNNING="false"
if systemctl is-active --quiet wazuh-agent; then
    SERVICE_RUNNING="true"
fi

# 2. Check Local Configuration
CONFIG_MANAGER_IP=""
CONFIG_AGENT_NAME=""
CONFIG_FILE="/var/ossec/etc/ossec.conf"

if [ -f "$CONFIG_FILE" ]; then
    # Extract manager IP using simple grep/sed (xml parsing is safer but this is sufficient for simple check)
    CONFIG_MANAGER_IP=$(grep "<address>" "$CONFIG_FILE" | head -1 | sed -e 's/.*<address>//' -e 's/<\/address>.*//' | tr -d '[:space:]')
    
    # Check for enrollment name in ossec.conf or ossec-agent.conf
    # Note: Name might be passed via enrollment flags and not strictly in conf, 
    # but we check if it was persisted or if client.keys exists.
    
    # Check client.keys for registered name
    if [ -f "/var/ossec/etc/client.keys" ]; then
        # client.keys format: ID Name IP Key
        REGISTERED_NAME_LOCAL=$(cat /var/ossec/etc/client.keys | grep "production-db-01" | awk '{print $2}')
        if [ "$REGISTERED_NAME_LOCAL" == "production-db-01" ]; then
             CONFIG_AGENT_NAME="production-db-01"
        fi
    fi
fi

# 3. Check Manager API Status
API_AGENT_STATUS="unknown"
API_AGENT_ID="unknown"
API_AGENT_IP="unknown"

TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    # Query for agent by name
    RESPONSE=$(curl -sk -X GET "${WAZUH_API_URL}/agents?search=production-db-01&select=status,id,ip" \
        -H "Authorization: Bearer ${TOKEN}")
    
    # Check if agent exists in response
    if echo "$RESPONSE" | grep -q '"total_affected_items":1'; then
        API_AGENT_STATUS=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['affected_items'][0]['status'])")
        API_AGENT_ID=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['affected_items'][0]['id'])")
        API_AGENT_IP=$(echo "$RESPONSE" | python3 -c "import sys, json; print(json.load(sys.stdin)['data']['affected_items'][0]['ip'])")
    else
        API_AGENT_STATUS="not_found"
    fi
else
    API_AGENT_STATUS="api_error"
fi

# Take final screenshot
take_screenshot /tmp/deploy_agent_final.png

# Create result JSON
TEMP_JSON=$(mktemp /tmp/result.XXXXXX.json)
cat > "$TEMP_JSON" << EOF
{
    "task_start": $TASK_START,
    "task_end": $TASK_END,
    "package_installed": $PACKAGE_INSTALLED,
    "service_running": $SERVICE_RUNNING,
    "config_manager_ip": "$CONFIG_MANAGER_IP",
    "local_registered_name": "$CONFIG_AGENT_NAME",
    "api_agent_status": "$API_AGENT_STATUS",
    "api_agent_id": "$API_AGENT_ID",
    "api_agent_ip": "$API_AGENT_IP",
    "screenshot_path": "/tmp/deploy_agent_final.png"
}
EOF

# Move to public location
safe_write_result "/tmp/task_result.json" "$(cat $TEMP_JSON)"
rm -f "$TEMP_JSON"

echo "Result exported:"
cat /tmp/task_result.json
echo "=== Export complete ==="