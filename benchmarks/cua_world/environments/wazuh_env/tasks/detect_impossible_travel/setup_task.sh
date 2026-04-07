#!/bin/bash
# pre_task: Setup for detect_impossible_travel
set -e

echo "=== Setting up detect_impossible_travel task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh Manager is running
if ! docker ps | grep -q "${WAZUH_MANAGER_CONTAINER}"; then
    echo "Starting Wazuh Manager..."
    docker-compose -f /home/ga/wazuh/docker-compose.yml up -d
    sleep 30
fi

# Clean up any existing rule 100050 from local_rules.xml to ensure clean state
echo "Cleaning up previous attempts..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "
    if grep -q 'id=\"100050\"' /var/ossec/etc/rules/local_rules.xml; then
        sed -i '/<rule id=\"100050\"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml
        /var/ossec/bin/wazuh-control restart
    fi
" || true

# Ensure the manager monitors /var/log/auth.log
# We check if 'auth.log' is configured in ossec.conf localfile section
echo "Verifying log monitoring..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "
    if ! grep -q '/var/log/auth.log' /var/ossec/etc/ossec.conf; then
        # Add auth.log monitoring if missing (simplified injection)
        sed -i '/<ossec_config>/a \  <localfile>\n    <location>/var/log/auth.log</location>\n    <log_format>syslog</log_format>\n  </localfile>' /var/ossec/etc/ossec.conf
        /var/ossec/bin/wazuh-control restart
        sleep 10
    fi
    # Ensure the file exists
    touch /var/log/auth.log
    chmod 666 /var/log/auth.log
"

# Open Firefox to Wazuh Dashboard for context
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"
sleep 5

# Open a terminal for the agent
su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x24+100+100 &"

# Capture initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="