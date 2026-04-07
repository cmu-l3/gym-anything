#!/bin/bash
# Pre-task setup for Audit Consult Services task
# Ensures YDBGui is accessible, Firefox is launched, and output directory exists.

echo "=== Setting up Audit Consult Services Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# 2. Ensure output directory exists and is clean
mkdir -p /home/ga/Documents
rm -f /home/ga/Documents/consult_services_audit.txt

# 3. Get VistA Container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# 4. Check VistA container is running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    # Try to start it (fallback)
    docker start vista-vehu 2>/dev/null || true
    sleep 5
fi

# 5. Ensure YDBGui is running without authentication
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui without authentication..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 6. Wait for YDBGui to be accessible
echo "Waiting for YDBGui to be ready..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui is accessible"
        break
    fi
    sleep 1
done

# 7. Kill existing Firefox and launch clean
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui Dashboard..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# 8. Wait for Firefox window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
        echo "Firefox window detected"
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 9. Wait for page load and dismiss popups
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# 10. Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo "Task: Audit Consult Services via ^GMR(123.5)"
echo "Output required: /home/ga/Documents/consult_services_audit.txt"
echo ""