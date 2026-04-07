#!/bin/bash
# Pre-task setup for Audit Mail Groups task

echo "=== Setting up Audit Mail Groups Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean up previous artifacts
rm -f /home/ga/Documents/mail_groups_audit.txt
mkdir -p /home/ga/Documents

# 2. Record task start time (for anti-gaming)
date +%s > /tmp/task_start_timestamp

# 3. Check VistA container
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "Starting VistA..."
    # Rely on environment post_start, but ensuring here doesn't hurt
    docker start vista-vehu 2>/dev/null || true
    sleep 5
fi

# 4. Get Container IP
CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
echo "$CONTAINER_IP" > /tmp/vista_container_ip

# 5. Ensure YDBGui is running (no auth)
echo "Checking YDBGui status..."
if ! docker exec vista-vehu ps aux 2>/dev/null | grep -q "ydbgui"; then
    echo "Starting YDBGui..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 3
fi

# 6. Wait for YDBGui availability
echo "Waiting for YDBGui..."
for i in {1..30}; do
    if curl -s "http://${CONTAINER_IP}:8089/" > /dev/null; then
        echo "YDBGui is ready."
        break
    fi
    sleep 1
done

# 7. Launch Firefox to YDBGui Dashboard
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox.log 2>&1 &"

# 8. Wait for Firefox window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "firefox"; then
        echo "Firefox detected."
        WID=$(DISPLAY=:1 wmctrl -l | grep -i "firefox" | head -1 | awk '{print $1}')
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 9. Dismiss popups
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# 10. Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Setup Complete ==="