#!/bin/bash
echo "=== Setting up Configure Wazuh Cluster Master task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Ensure Wazuh manager is running
if ! docker ps | grep -q "${WAZUH_MANAGER_CONTAINER}"; then
    echo "Starting Wazuh manager container..."
    docker start "${WAZUH_MANAGER_CONTAINER}"
    sleep 10
fi

# Ensure cluster is currently DISABLED in ossec.conf to provide a clean starting state
echo "Resetting cluster configuration to default (disabled)..."
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<cluster>/,/<\/cluster>/ s/<disabled>.*<\/disabled>/<disabled>yes<\/disabled>/' /var/ossec/etc/ossec.conf"
docker exec "${WAZUH_MANAGER_CONTAINER}" bash -c "sed -i '/<cluster>/,/<\/cluster>/ s/<node_type>.*<\/node_type>/<node_type>master<\/node_type>/' /var/ossec/etc/ossec.conf"

# Restart manager to ensure clean state
echo "Restarting manager to apply clean state..."
restart_wazuh_manager

# Record initial file modification time
INITIAL_MTIME=$(docker exec "${WAZUH_MANAGER_CONTAINER}" stat -c %Y /var/ossec/etc/ossec.conf 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_conf_mtime.txt

# Open a terminal for the agent to work in
if ! pgrep -f "gnome-terminal" > /dev/null; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=100x30 &"
    sleep 2
fi

# Maximize terminal
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="