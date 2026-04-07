#!/bin/bash
# Setup for Implement Custom Active Response task
echo "=== Setting up implement_custom_quarantine_ar task ==="

source /workspace/scripts/task_utils.sh

# Record start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# 1. Clean up any previous run artifacts
echo "Cleaning up directories..."
rm -rf /home/ga/contracts
rm -rf /home/ga/quarantine
rm -f /home/ga/quarantine.sh

# 2. Reset Wazuh Configuration (Idempotency)
echo "Resetting Wazuh configuration..."
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Remove custom script if exists
docker exec "${CONTAINER}" rm -f /var/ossec/active-response/bin/quarantine.sh

# Revert ossec.conf (remove our specific blocks if they exist from previous runs)
# This is a basic cleanup sed; in a real env we might use a clean backup
docker exec "${CONTAINER}" sed -i '/<name>cmd-quarantine<\/name>/,+4d' /var/ossec/etc/ossec.conf
docker exec "${CONTAINER}" sed -i '/<command>cmd-quarantine<\/command>/,+5d' /var/ossec/etc/ossec.conf
# Remove directory monitoring for contracts
docker exec "${CONTAINER}" sed -i '/\/home\/ga\/contracts/d' /var/ossec/etc/ossec.conf

# Revert local_rules.xml (remove rule 100550)
docker exec "${CONTAINER}" sed -i '/id="100550"/,+5d' /var/ossec/etc/rules/local_rules.xml

# Restart manager to ensure clean state
echo "Restarting Wazuh manager to ensure clean state..."
docker exec "${CONTAINER}" /var/ossec/bin/wazuh-control restart > /dev/null 2>&1
sleep 5

# 3. Open Firefox to Dashboard (Helpful starting state)
echo "Opening Wazuh dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 4. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="