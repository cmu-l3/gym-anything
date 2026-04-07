#!/bin/bash
# setup_task.sh for create_custom_webhook_integration

echo "=== Setting up Custom Webhook Integration Task ==="

source /workspace/scripts/task_utils.sh

CONTAINER="wazuh-wazuh.manager-1"
SHELL_SCRIPT="/var/ossec/integrations/custom-slack-alerts"
PYTHON_SCRIPT="/var/ossec/integrations/custom-slack-alerts.py"
CONFIG_FILE="/var/ossec/etc/ossec.conf"

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 2. Ensure Wazuh manager is running
if ! docker ps | grep -q "$CONTAINER"; then
    echo "Starting Wazuh containers..."
    docker start "$CONTAINER"
    sleep 10
fi

# 3. Clean up previous task artifacts inside the container
echo "Cleaning up existing integration files..."
docker exec "$CONTAINER" rm -f "$SHELL_SCRIPT" "$PYTHON_SCRIPT" 2>/dev/null || true

# 4. Clean up ossec.conf (remove integration block if exists)
# We look for the custom integration name and remove the XML block
echo "Cleaning up ossec.conf..."
docker exec "$CONTAINER" bash -c "
    if grep -q '<name>custom-slack-alerts</name>' $CONFIG_FILE; then
        # Use sed to remove the integration block. 
        # This is a bit complex with sed, so we'll use a safer approach:
        # Restore from backup if exists, or try to delete the block carefully
        cp $CONFIG_FILE ${CONFIG_FILE}.bak
        # Delete lines between <integration> and </integration> containing our name
        # Note: This is a simplified cleanup. For robustness, we might just reload a clean config.
        sed -i '/<name>custom-slack-alerts<\/name>/,/<\/integration>/d' $CONFIG_FILE
        sed -i '/<integration>/ { N; /<name>custom-slack-alerts<\/name>/d; }' $CONFIG_FILE
    fi
" 2>/dev/null || true

# Ensure dashboard is open
ensure_firefox_wazuh "https://localhost/app/wz-home"
sleep 5

# Maximize and focus
WID=$(get_firefox_window_id)
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -ia "$WID"
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
fi

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="