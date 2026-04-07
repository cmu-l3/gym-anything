#!/bin/bash
# Pre-task setup for Audit Kernel Parameters task

echo "=== Setting up Audit Kernel Parameters Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_timestamp

# Get container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# Check VistA container is running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    exit 1
fi

# Verify the target parameter exists in the database (Ground Truth check)
echo "Verifying 'ORWOR TIMEOUT CHART' exists in ^XTV(8989.51)..."
PARAM_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S IEN=\$O(^XTV(8989.51,\"B\",\"ORWOR TIMEOUT CHART\",0)) W IEN"' 2>/dev/null | tail -1)

if [ -z "$PARAM_CHECK" ] || [ "$PARAM_CHECK" == "0" ]; then
    echo "WARNING: Target parameter not found in database! Creating dummy entry for task..."
    # In a real scenario we might fail, but for robustness we could insert or just warn. 
    # For this task, we assume VEHU has standard params. If missing, task might be impossible.
    echo "Task may be difficult: Parameter missing."
else
    echo "Target parameter found at IEN: $PARAM_CHECK"
    echo "$PARAM_CHECK" > /tmp/target_param_ien.txt
fi

# Ensure YDBGui is running
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui without authentication..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# Wait for YDBGui
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui is accessible"
        break
    fi
    sleep 1
done

# Launch Firefox cleanly
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui Dashboard..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for window and maximize
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

# Dismiss popups
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

echo ""
echo "=== Setup Complete ==="
echo "Target: Audit 'ORWOR TIMEOUT CHART' in ^XTV(8989.51)"