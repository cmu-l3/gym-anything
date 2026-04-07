#!/bin/bash
set -e
echo "=== Setting up Implement Label-Based Log Monitoring task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Ensure Wazuh manager is running
if ! docker ps | grep -q "$CONTAINER"; then
    echo "Starting Wazuh manager container..."
    docker-compose -f /home/ga/wazuh/docker-compose.yml up -d wazuh.manager
    wait_for_service "Wazuh Manager" "docker exec $CONTAINER ps aux | grep -q wazuh-modulesd" 60
fi

# Clean up previous state (Anti-gaming/Clean slate)
echo "Cleaning up configurations..."
docker exec "$CONTAINER" bash -c "
    # Backup config if not backed up
    if [ ! -f /var/ossec/etc/ossec.conf.bak ]; then
        cp /var/ossec/etc/ossec.conf /var/ossec/etc/ossec.conf.bak
    fi
    
    # Restore config to remove labels/localfiles from previous runs
    # (Simple sed removal for specific lines we might have added)
    sed -i '/<label key=\"compliance\">/d' /var/ossec/etc/ossec.conf
    sed -i '/payment_app.log/d' /var/ossec/etc/ossec.conf
    
    # Remove custom rule if exists
    sed -i '/id=\"100250\"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml
    
    # Remove the log file
    rm -f /var/log/payment_app.log
" 2>/dev/null || true

# Restart manager to ensure clean state loaded
echo "Restarting manager to apply clean state..."
restart_wazuh_manager > /dev/null

# Open Firefox to dashboard (optional for agent, but good for context)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="