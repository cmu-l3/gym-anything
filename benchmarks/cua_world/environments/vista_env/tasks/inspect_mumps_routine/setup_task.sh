#!/bin/bash
set -e

echo "=== Setting up Inspect MUMPS Routine Task ==="

# 1. Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 2. Record task start time (anti-gaming)
date +%s > /tmp/task_start_timestamp

# 3. Ensure VistA is running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "Starting VistA container..."
    # The env start hook usually handles this, but safety first
    /workspace/scripts/setup_vista.sh
fi

# 4. Get Container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi

# 5. Ensure YDBGui is running (no auth)
echo "Checking YDBGui status..."
if ! docker exec vista-vehu ps aux 2>/dev/null | grep -q "ydbgui"; then
    echo "Starting YDBGui..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# 6. Extract Ground Truth (The actual source code of XLFDT)
echo "Extracting ground truth source code..."
# We use ZPRINT (ZP) command in GT.M/YottaDB to print the routine
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "ZP ^XLFDT"' > /tmp/xlfdt_ground_truth.txt 2>/dev/null || true
head -n 20 /tmp/xlfdt_ground_truth.txt > /tmp/xlfdt_sample.txt
echo "Ground truth extracted:"
head -n 5 /tmp/xlfdt_sample.txt

# 7. Reset/Launch Firefox
pkill -9 firefox 2>/dev/null || true
sleep 1

YDBGUI_URL="http://${CONTAINER_IP}:8089/"
echo "Launching Firefox to $YDBGUI_URL"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# 8. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "firefox"; then
        echo "Firefox detected"
        sleep 1
        WID=$(DISPLAY=:1 wmctrl -l | grep -i firefox | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID"
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz
        break
    fi
    sleep 1
done

# 9. Dismiss popups
sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 10. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="