#!/bin/bash
echo "=== Setting up Detect Ephemeral Account Task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh Manager is running
echo "Checking Wazuh Manager status..."
if ! docker ps | grep -q "wazuh.manager"; then
    echo "Starting Wazuh Manager..."
    docker-compose -f /home/ga/wazuh/docker-compose.yml up -d wazuh.manager
    sleep 30
fi

# Reset local_rules.xml to a clean state (empty group)
# This prevents previous run artifacts from interfering
echo "Resetting local_rules.xml..."
EMPTY_RULES='<!-- Local rules -->
<group name="local,syslog,">
</group>
'
# Write to temp file then copy to container
echo "$EMPTY_RULES" > /tmp/local_rules_reset.xml
docker cp /tmp/local_rules_reset.xml wazuh-wazuh.manager-1:/var/ossec/etc/rules/local_rules.xml
docker exec wazuh-wazuh.manager-1 chown wazuh:wazuh /var/ossec/etc/rules/local_rules.xml
docker exec wazuh-wazuh.manager-1 chmod 660 /var/ossec/etc/rules/local_rules.xml

# Restart manager to apply clean state
echo "Restarting Wazuh Manager..."
restart_wazuh_manager

# Ensure Firefox is open to the Dashboard
echo "Launching Dashboard..."
ensure_firefox_wazuh "${WAZUH_URL_HOME}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="