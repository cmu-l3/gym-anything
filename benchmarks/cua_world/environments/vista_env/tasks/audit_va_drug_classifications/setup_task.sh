#!/bin/bash
# Pre-task setup for Audit VA Drug Classifications
# Ensures VistA is running, YDBGui is accessible, and cleans up previous artifacts.

echo "=== Setting up Audit VA Drug Classifications Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/drug_class_audit.txt
mkdir -p /home/ga/Documents

# 2. Check VistA container status
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    # Try to start it (fallback)
    /workspace/scripts/setup_vista.sh
fi

# Get container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# 3. Verify VA Drug Class file exists (Ground Truth Check)
# Check if ^PS(50.605) has data
echo "Verifying ^PS(50.605) global..."
HAS_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^PS(50.605))"' 2>/dev/null | tail -1)

if [ "$HAS_DATA" == "0" ] || [ -z "$HAS_DATA" ]; then
    echo "WARNING: ^PS(50.605) appears empty or inaccessible."
else
    echo "VA Drug Class global confirmed."
fi

# 4. Ensure YDBGui is running
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 5. Launch Firefox
# Kill existing Firefox
pkill -9 firefox 2>/dev/null || true
sleep 1

YDBGUI_URL="http://${CONTAINER_IP}:8089/"
echo "Launching Firefox at $YDBGUI_URL..."
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
        echo "Firefox window detected."
        # Maximize
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Dismiss popups
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 6. Capture initial state
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Setup Complete ==="