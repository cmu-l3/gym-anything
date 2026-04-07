#!/bin/bash
# Pre-task setup for Audit Key Holders task
# Ensures VistA is running, YDBGui is accessible, and the XUPROG key has data.

echo "=== Setting up Audit Key Holders Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Function for fallback screenshot
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Record task start time
date +%s > /tmp/task_start_timestamp

# 1. Check/Start VistA Container
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "Starting VistA container..."
    # The environment should handle this, but we double-check
    docker start vista-vehu 2>/dev/null || true
    sleep 5
fi

# Get Container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# 2. Ensure XUPROG key has at least one holder (Seed Data)
# We add DUZ 1 (System Manager) to XUPROG just in case it's missing, to ensure task is solvable.
echo "Seeding XUPROG security key data..."
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S ^XUSEC(\"XUPROG\",1)=\"\""' 2>/dev/null
# Also add a random user (DUZ 42) for variety
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S ^XUSEC(\"XUPROG\",42)=\"\""' 2>/dev/null

# 3. Ensure YDBGui is running (No Auth)
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui without authentication..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 4. Launch Firefox
# Kill existing Firefox to ensure clean start
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui Dashboard..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox window
echo "Waiting for Firefox..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
        echo "Firefox detected."
        # Maximize
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Wait for page load and dismiss popups
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 5. Capture Initial State
take_screenshot /tmp/task_initial_screenshot.png

echo "=== Setup Complete ==="
echo "Target: ^XUSEC(\"XUPROG\")"