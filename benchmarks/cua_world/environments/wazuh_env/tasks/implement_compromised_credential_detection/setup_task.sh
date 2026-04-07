#!/bin/bash
# setup_task.sh for implement_compromised_credential_detection

set -e
echo "=== Setting up task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh manager is running
if ! docker ps | grep -q "${WAZUH_MANAGER_CONTAINER}"; then
    echo "Starting Wazuh containers..."
    docker-compose -f /home/ga/wazuh/docker-compose.yml up -d
    wait_for_service "Wazuh Manager" "docker exec ${WAZUH_MANAGER_CONTAINER} /var/ossec/bin/wazuh-control status" 60
fi

# Prepare the input data file
echo "Creating breached users list..."
cat > /home/ga/breached_users.txt << EOF
admin
root
oracle
test
guest
postgres
nagios
ansible
vagrant
ubuntu
EOF
chown ga:ga /home/ga/breached_users.txt

# Clean up any previous attempts (anti-gaming/reset)
echo "Cleaning previous state..."
docker exec "${WAZUH_MANAGER_CONTAINER}" rm -f /var/ossec/etc/lists/compromised_users
docker exec "${WAZUH_MANAGER_CONTAINER}" rm -f /var/ossec/etc/lists/compromised_users.cdb

# Reset ossec.conf to remove the list reference if it exists
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<list>etc\/lists\/compromised_users<\/list>/d' /var/ossec/etc/ossec.conf"

# Reset local_rules.xml
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "echo '<!-- Local rules -->' > /var/ossec/etc/rules/local_rules.xml"

# Restart manager to ensure clean state
restart_wazuh_manager

# Open Firefox to dashboard (helpful context, though task is largely backend)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="