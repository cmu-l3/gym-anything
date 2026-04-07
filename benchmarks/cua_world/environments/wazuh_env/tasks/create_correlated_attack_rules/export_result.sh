#!/bin/bash
echo "=== Exporting create_correlated_attack_rules results ==="

source /workspace/scripts/task_utils.sh

TASK_START=$(cat /tmp/task_start_time.txt 2>/dev/null || echo "0")
VERIFICATION_FILE="/home/ga/correlated_rules_verification.json"

# 1. Export the Agent's Verification File
if [ -f "$VERIFICATION_FILE" ]; then
    cp "$VERIFICATION_FILE" /tmp/agent_verification.json
    VERIFICATION_EXISTS="true"
else
    echo "{}" > /tmp/agent_verification.json
    VERIFICATION_EXISTS="false"
fi

# 2. Export the actual local_rules.xml from the container
echo "Extracting local_rules.xml from container..."
docker cp "${WAZUH_MANAGER_CONTAINER}:/var/ossec/etc/rules/local_rules.xml" /tmp/local_rules.xml 2>/dev/null || echo "<error>Could not copy rules file</error>" > /tmp/local_rules.xml

# 3. Query API for the rules (Independent verification of loaded state)
echo "Querying API for rule status..."
TOKEN=$(get_api_token)
if [ -n "$TOKEN" ]; then
    curl -sk -X GET "${WAZUH_API_URL}/rules?rule_ids=100300,100301,100302" \
        -H "Authorization: Bearer ${TOKEN}" > /tmp/api_rules_check.json
else
    echo "{\"error\": \"Could not get API token\"}" > /tmp/api_rules_check.json
fi

# 4. Check if manager is running
MANAGER_RUNNING="false"
if docker exec "${WAZUH_MANAGER_CONTAINER}" /var/ossec/bin/wazuh-control status 2>/dev/null | grep -q "wazuh-analysisd is running"; then
    MANAGER_RUNNING="true"
fi

# 5. Take final screenshot
take_screenshot /tmp/task_final.png

# 6. Create Result JSON
cat > /tmp/task_result.json << EOF
{
    "task_start_time": $TASK_START,
    "verification_file_exists": $VERIFICATION_EXISTS,
    "manager_running": $MANAGER_RUNNING,
    "timestamp": "$(date -Iseconds)"
}
EOF

# Ensure permissions
chmod 666 /tmp/task_result.json /tmp/local_rules.xml /tmp/api_rules_check.json /tmp/agent_verification.json 2>/dev/null || true

echo "=== Export complete ==="