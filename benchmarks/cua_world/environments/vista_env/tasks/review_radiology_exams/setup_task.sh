#!/bin/bash
# Pre-task setup for Review Radiology Exams task
# Ensures VistA is running, Radiology globals exist, and YDBGui is ready.

echo "=== Setting up Review Radiology Exams Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time for anti-gaming checks
date +%s > /tmp/task_start_timestamp

# 2. Get container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# 3. Check VistA container is running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    # Try to start it (fallback)
    docker start vista-vehu
    sleep 5
fi

# 4. Verify Radiology Globals Existence (Infrastructure Check)
echo "Verifying Radiology globals..."
# Check ^RA(71) - Procedures
PROC_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^RA(71))"' 2>/dev/null | tail -1)
# Check ^RA(75.1) - Orders
ORDER_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^RA(75.1))"' 2>/dev/null | tail -1)

if [ "$PROC_CHECK" == "0" ]; then
    echo "WARNING: ^RA(71) global missing or empty. Task may be difficult."
else
    echo "Rad Procedures (^RA(71)) confirmed."
fi

# 5. Ensure YDBGui is running without authentication
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui without authentication..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 6. Wait for YDBGui accessibility
echo "Waiting for YDBGui..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui is accessible"
        break
    fi
    sleep 1
done

# 7. Launch Firefox (Clean state)
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui Dashboard..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
        echo "Firefox window detected"
        # Maximize
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 5
# Dismiss popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 8. Capture Initial State
if type take_screenshot &>/dev/null; then
    take_screenshot /tmp/task_initial_screenshot.png
else
    DISPLAY=:1 scrot /tmp/task_initial_screenshot.png 2>/dev/null || true
fi

echo "=== Task Setup Complete ==="