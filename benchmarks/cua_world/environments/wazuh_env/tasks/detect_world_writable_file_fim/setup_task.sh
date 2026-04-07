#!/bin/bash
echo "=== Setting up detect_world_writable_file_fim task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. Create the target directory
TARGET_DIR="/opt/secure_configs"
if [ ! -d "$TARGET_DIR" ]; then
    mkdir -p "$TARGET_DIR"
    # Set default permissions (root owned, not world writable)
    chmod 750 "$TARGET_DIR"
    chown root:root "$TARGET_DIR"
    echo "Created $TARGET_DIR"
fi

# 2. Ensure Wazuh Manager is running
echo "Checking Wazuh Manager status..."
if ! is_wazuh_manager_running; then
    echo "Starting Wazuh Manager..."
    docker start "${WAZUH_MANAGER_CONTAINER}"
    wait_for_service "Wazuh Manager" "check_api_health" 60
fi

# 3. Open Firefox to Wazuh Dashboard (Standard starting state)
echo "Opening Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 4. Clean up previous artifacts (if any) to prevent false positives
# Remove rule 110001 if it exists in local_rules.xml
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<rule id=\"110001\"/,/<\/rule>/d' /var/ossec/etc/rules/local_rules.xml" 2>/dev/null || true

# Remove config for /opt/secure_configs if it exists
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/\/opt\/secure_configs/d' /var/ossec/etc/ossec.conf" 2>/dev/null || true

# Restart manager to apply clean state if changes were made
restart_wazuh_manager

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="