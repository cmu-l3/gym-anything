#!/bin/bash
# Pre-task setup for Review Surgery Cases task
# Ensures VistA is running, surgery data exists, and YDBGui is ready.

echo "=== Setting up Review Surgery Cases Task ==="

# 1. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_timestamp

# 2. Verify VistA Container Status
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    exit 1
fi
echo "VistA container: RUNNING"

# 3. Get Container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
echo "$CONTAINER_IP" > /tmp/vista_container_ip
echo "VistA IP: $CONTAINER_IP"

# 4. Check for Surgery Data in ^SRF
# We query the database directly to ensure the task is possible
echo "Checking for surgery data in ^SRF..."
SURGERY_COUNT=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S C=0,X=0 F  S X=\$O(^SRF(X)) Q:X=\"\"  S C=C+1 S:C>999 X=\"\" W:X=\"\" C"' 2>/dev/null | tail -1)
SURGERY_COUNT=${SURGERY_COUNT:-0}

echo "$SURGERY_COUNT" > /tmp/initial_surgery_count
echo "Surgery cases found: $SURGERY_COUNT"

if [ "$SURGERY_COUNT" -eq "0" ]; then
    echo "WARNING: No surgery cases found. Task may be difficult."
    # We don't fail here to allow for edge case handling in verifier, 
    # but in a real scenario we might want to inject data here.
fi

# 5. Ensure YDBGui is running (restart without auth if needed)
YDBGUI_PID=$(docker exec vista-vehu pgrep -f "ydbgui" 2>/dev/null)
if [ -z "$YDBGUI_PID" ]; then
    echo "Starting YDBGui..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 6. Wait for Web Interface
echo "Waiting for YDBGui..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui accessible."
        break
    fi
    sleep 1
done

# 7. Launch Firefox to Dashboard (Clean State)
pkill -9 firefox 2>/dev/null || true
sleep 1

YDBGUI_URL="http://${CONTAINER_IP}:8089/"
echo "Launching Firefox to $YDBGUI_URL"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# 8. Wait for Window & Maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        echo "Firefox window maximized."
        break
    fi
    sleep 1
done

# 9. Dismiss popups/focus
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 10. Initial Screenshot
DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="