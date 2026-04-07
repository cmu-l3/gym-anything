#!/bin/bash
echo "=== Setting up monitor_config_diffs task ==="

source /workspace/scripts/task_utils.sh

# Record task start time
date +%s > /tmp/task_start_time.txt

CONTAINER="wazuh-wazuh.manager-1"
TARGET_FILE="/var/ossec/etc/critical_app.conf"

# 1. Create the dummy config file inside the container
echo "Creating target file $TARGET_FILE inside container..."
docker exec "$CONTAINER" bash -c "echo 'app_name=CriticalSystem' > $TARGET_FILE"
docker exec "$CONTAINER" bash -c "echo 'debug_mode=false' >> $TARGET_FILE"
docker exec "$CONTAINER" bash -c "echo 'max_connections=100' >> $TARGET_FILE"
docker exec "$CONTAINER" chown root:wazuh "$TARGET_FILE"
docker exec "$CONTAINER" chmod 660 "$TARGET_FILE"

# 2. Ensure ossec.conf is clean (remove any previous config for this file)
echo "Ensuring clean state for ossec.conf..."
# We accept that editing XML via sed is fragile, but sufficient for reset
docker exec "$CONTAINER" bash -c "sed -i '\|<directories.*$TARGET_FILE|d' /var/ossec/etc/ossec.conf" 2>/dev/null || true

# 3. Ensure Wazuh Dashboard is ready
echo "Waiting for Wazuh Dashboard..."
ensure_firefox_wazuh "${WAZUH_URL_CONFIG}"
sleep 5

# 4. Open a terminal for the agent (since they might need docker exec)
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x24+200+200 &"
    sleep 2
fi

# 5. Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "Target file created: $TARGET_FILE (inside container $CONTAINER)"
echo "Initial content: debug_mode=false"