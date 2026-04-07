#!/bin/bash
echo "=== Setting up configure_remote_syslog_ingestion task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Clean existing state: Remove any remote syslog config on port 514
echo "Cleaning ossec.conf..."
docker exec "${CONTAINER}" sed -i '/<remote>/,/<\/remote>/ {
    /<port>514<\/port>/d
}' /var/ossec/etc/ossec.conf

# 2. Clean existing state: Remove custom rule 100100
echo "Cleaning local_rules.xml..."
docker exec "${CONTAINER}" sed -i '/id="100100"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml

# 3. Restart manager to ensure clean state
echo "Restarting Wazuh manager..."
restart_wazuh_manager

# 4. Wait for API to be ready
echo "Waiting for API..."
for i in {1..30}; do
    if check_api_health; then
        echo "API is ready."
        break
    fi
    sleep 2
done

# 5. Open Firefox to Dashboard
echo "Opening Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 6. Capture initial state screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="