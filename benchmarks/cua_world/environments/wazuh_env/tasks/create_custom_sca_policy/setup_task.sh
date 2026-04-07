#!/bin/bash
set -e
echo "=== Setting up create_custom_sca_policy task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

# Container name
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# 1. Clean up any previous attempts
echo "Cleaning up previous artifacts..."
docker exec "${CONTAINER}" rm -f /var/ossec/etc/sca/payment_gateway_audit.yml 2>/dev/null || true

# Remove reference from ossec.conf if it exists
docker exec "${CONTAINER}" bash -c "sed -i '\|etc/sca/payment_gateway_audit.yml|d' /var/ossec/etc/ossec.conf" 2>/dev/null || true

# 2. Setup Dummy Application
echo "Setting up dummy application environment..."
docker exec "${CONTAINER}" bash -c "
    # Create directories
    mkdir -p /opt/payment_gateway/config
    mkdir -p /opt/payment_gateway/logs

    # Create files with specific states for auditing
    
    # 1. keys.pem: Should be 400. We set to 644 (FAIL condition)
    touch /opt/payment_gateway/config/keys.pem
    chmod 644 /opt/payment_gateway/config/keys.pem
    chown root:root /opt/payment_gateway/config/keys.pem

    # 2. logs dir: Should be root:root. We set to root:root (PASS condition)
    chown root:root /opt/payment_gateway/logs
    chmod 755 /opt/payment_gateway/logs

    # 3. app.conf: Should have debug=false. We set debug=true (FAIL condition)
    echo 'debug=true' > /opt/payment_gateway/config/app.conf
    chmod 600 /opt/payment_gateway/config/app.conf
"

# 3. Restart manager to ensure clean state
echo "Restarting Wazuh Manager..."
restart_wazuh_manager

# 4. Wait for API to be ready
echo "Waiting for API..."
until check_api_health; do
    echo "  Waiting for API..."
    sleep 5
done

# 5. Open VS Code or Terminal for the agent (Simulate starting environment)
# Since this is a CLI/Config task, we ensure a terminal is handy or Dashboard is open
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="