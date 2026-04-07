#!/bin/bash
# Setup for implement_user_agent_whitelist task

echo "=== Setting up User-Agent Whitelist Task ==="

source /workspace/scripts/task_utils.sh

# Container name
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous attempts (Anti-Gaming / Clean State)
echo "Cleaning up potential stale files in container..."
docker exec "${CONTAINER}" rm -f /var/ossec/etc/lists/authorized_user_agents
docker exec "${CONTAINER}" rm -f /var/ossec/etc/lists/authorized_user_agents.cdb

# 2. Reset local_rules.xml to a safe baseline
echo "Resetting local_rules.xml..."
cat > /tmp/baseline_rules.xml << EOF
<!-- Local rules -->
<group name="local,syslog,">
  <!-- Default empty local rules -->
</group>
EOF
docker cp /tmp/baseline_rules.xml "${CONTAINER}:/var/ossec/etc/rules/local_rules.xml"
docker exec "${CONTAINER}" chown root:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec "${CONTAINER}" chmod 660 /var/ossec/etc/rules/local_rules.xml
rm -f /tmp/baseline_rules.xml

# 3. Clean ossec.conf of any previous list definitions for this specific list
echo "Cleaning ossec.conf..."
docker exec "${CONTAINER}" sed -i '/authorized_user_agents/d' /var/ossec/etc/ossec.conf

# 4. Restart Manager to ensure clean memory state
echo "Restarting Wazuh manager..."
restart_wazuh_manager

# 5. Ensure Firefox is open (agent might want to use Dashboard, though this is CLI heavy)
echo "Ensuring Firefox is running..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# 6. Capture initial state
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="