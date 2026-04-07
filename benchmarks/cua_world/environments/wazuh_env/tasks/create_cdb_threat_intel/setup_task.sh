#!/bin/bash
# Setup script for create_cdb_threat_intel task
set -e

echo "=== Setting up create_cdb_threat_intel task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh manager is running
if ! check_api_health; then
    echo "Wazuh API not ready, waiting..."
    # Attempt to start if not running (though environment should handle this)
    restart_wazuh_manager
    sleep 30
fi

# Authenticate to get token
TOKEN=$(get_api_token)

# 1. Clean up any existing state (idempotency)
# Check if list exists
echo "Checking for existing list..."
LIST_CHECK=$(curl -sk -X GET "${WAZUH_API_URL}/lists/files/threat-intel-blocklist" -H "Authorization: Bearer ${TOKEN}")
if echo "$LIST_CHECK" | grep -q "threat-intel-blocklist"; then
    echo "Removing existing threat-intel-blocklist..."
    curl -sk -X DELETE "${WAZUH_API_URL}/lists/files/threat-intel-blocklist" -H "Authorization: Bearer ${TOKEN}"
fi

# Check if rule exists in local_rules.xml
echo "Checking for existing rule 100100..."
# We can't easily delete just one rule via API without parsing XML, but we can check if it exists
# to record initial state properly.
# Ideally, we restore local_rules.xml to a clean state.
echo "Restoring clean local_rules.xml..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c 'cat > /var/ossec/etc/rules/local_rules.xml << EOF
<group name="local,syslog,">
  <!-- Rules added here -->
</group>
EOF'
docker exec "${WAZUH_MANAGER_CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "${WAZUH_MANAGER_CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to ensure clean state takes effect
echo "Restarting manager to apply clean state..."
restart_wazuh_manager

# 2. Record Initial State
echo "Recording initial state..."
INITIAL_LISTS=$(wazuh_api GET "/lists?pretty=true")
INITIAL_RULES=$(wazuh_api GET "/rules?rule_ids=100100")

cat > /tmp/initial_state.json << EOF
{
    "lists": $INITIAL_LISTS,
    "rules": $INITIAL_RULES,
    "timestamp": $(date +%s)
}
EOF

# 3. Setup UI
echo "Setting up UI..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task Setup Complete ==="