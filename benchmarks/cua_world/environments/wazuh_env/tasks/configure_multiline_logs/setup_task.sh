#!/bin/bash
echo "=== Setting up Configure Multiline Logs task ==="

source /workspace/scripts/task_utils.sh

# Container name
CONTAINER="${WAZUH_MANAGER_CONTAINER}"

# Record start time
date +%s > /tmp/task_start_time.txt

# 1. Create the dummy log file with some initial content
echo "Creating dummy Java log file..."
docker exec "${CONTAINER}" bash -c 'cat > /var/log/billing_app.log <<EOF
2023-11-15 08:00:01 INFO  Init - System starting
2023-11-15 08:00:02 INFO  Init - Database connected
EOF'
docker exec "${CONTAINER}" chmod 644 /var/log/billing_app.log
docker exec "${CONTAINER}" chown root:root /var/log/billing_app.log

# 2. Reset ossec.conf to ensure clean state
# - Disable logall
# - Remove any existing config for billing_app.log
echo "Resetting ossec.conf..."
docker exec "${CONTAINER}" bash -c "
    sed -i 's|<logall>yes</logall>|<logall>no</logall>|g' /var/ossec/etc/ossec.conf
    # Remove any existing localfile block for billing_app.log (naive XML removal using sed/pattern match)
    # This removes the file path and 5 lines before/after - sufficient for a reset
    if grep -q '/var/log/billing_app.log' /var/ossec/etc/ossec.conf; then
       sed -i '/<localfile>/,/<\/localfile>/ { 
           /billing_app.log/d 
       }' /var/ossec/etc/ossec.conf
       # Cleanup empty blocks if any (simplified cleanup)
       sed -i '/<localfile>\s*<\/localfile>/d' /var/ossec/etc/ossec.conf
    fi
"

# 3. Clear archives.log if it exists
docker exec "${CONTAINER}" bash -c 'echo "" > /var/ossec/logs/archives/archives.log'

# 4. Restart manager to apply clean state
echo "Restarting Wazuh manager..."
restart_wazuh_manager

# 5. Open Firefox to Dashboard (standard start state)
ensure_firefox_wazuh "${WAZUH_DASHBOARD_URL}"

# 6. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup complete ==="