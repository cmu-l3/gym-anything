#!/bin/bash
# Pre-task setup for Investigate Hospital Locations task

echo "=== Setting up Investigate Hospital Locations Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Helper for screenshots if not sourced
if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

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
echo "VistA container: RUNNING"

# Verify Hospital Location data exists in ^SC
echo "Checking Hospital Location data in ^SC..."
# Simple check if global exists
FIRST_IEN=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^SC(0))"' 2>/dev/null | tail -1)

if [ -z "$FIRST_IEN" ] || [ "$FIRST_IEN" = "" ]; then
    echo "WARNING: No Hospital Location records found in ^SC"
    echo "0" > /tmp/sc_initial_count
else
    echo "Hospital Location data exists (first IEN: $FIRST_IEN)"
    echo "exists" > /tmp/sc_initial_count
fi

# Capture Ground Truth: List first 20 locations and their types for verification
echo "Capturing ground truth data..."
# This M command iterates ^SC and prints Name^Type for first 20 entries
GT_DATA=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^SC(X)) Q:X=\"\"!(N>=20)  S N=N+1 S D=\$G(^SC(X,0)) W \$P(D,U,1),\"^\",\$P(D,U,3),! "' 2>/dev/null)
echo "$GT_DATA" > /tmp/hospital_locations_gt.txt
echo "Ground truth captured."

# Ensure YDBGui is running
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui without authentication..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# Wait for YDBGui accessibility
echo "Waiting for YDBGui..."
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui is accessible"
        break
    fi
    sleep 1
done

# Kill existing Firefox and launch clean
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui Dashboard..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox window
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

sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Initial screenshot
take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Investigate ^SC (Hospital Location) global"
echo "Instructions: Open Global viewer, navigate to ^SC, browse 5+ entries, find Clinic/Ward types."
echo ""