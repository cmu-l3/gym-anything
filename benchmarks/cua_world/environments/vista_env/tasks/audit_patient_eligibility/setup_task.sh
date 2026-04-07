#!/bin/bash
# Pre-task setup for Audit Patient Eligibility task
# Ensures VistA is running, YDBGui is accessible, and target patient exists

echo "=== Setting up Audit Patient Eligibility Task ==="

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

# Ensure YDBGui is running
echo "Checking YDBGui status..."
if ! docker exec vista-vehu ps aux 2>/dev/null | grep -q ydbgui; then
    echo "Starting YDBGui..."
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 > /home/vehu/log/ydbgui-task.log 2>&1 &'
    sleep 5
fi

# Wait for YDBGui accessibility
echo "Waiting for YDBGui..."
for i in {1..30}; do
    if curl -s "http://${CONTAINER_IP}:8089/" > /dev/null; then
        echo "YDBGui is accessible"
        break
    fi
    sleep 1
done

# Verify Target Patient (DFN 1) and Reference Files exist
echo "Verifying database state..."
# Check DFN 1
PATIENT_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DPT(1,0))"' 2>/dev/null | tr -d '\r\n')
# Check File 21
FILE21_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DIC(21,0))"' 2>/dev/null | tr -d '\r\n')
# Check File 8
FILE8_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DIC(8,0))"' 2>/dev/null | tr -d '\r\n')

if [[ "$PATIENT_CHECK" == "0" || "$FILE21_CHECK" == "0" || "$FILE8_CHECK" == "0" ]]; then
    echo "ERROR: Required database globals missing!"
    exit 1
fi

# Kill existing Firefox
pkill -9 firefox 2>/dev/null || true
sleep 1

# Launch Firefox
echo "Launching Firefox..."
YDBGUI_URL="http://${CONTAINER_IP}:8089/"
su - ga -c "DISPLAY=:1 firefox '${YDBGUI_URL}' > /tmp/firefox_task.log 2>&1 &"

# Wait for Firefox window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi firefox; then
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

# Initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_screenshot.png 2>/dev/null || true

echo "=== Setup Complete ==="