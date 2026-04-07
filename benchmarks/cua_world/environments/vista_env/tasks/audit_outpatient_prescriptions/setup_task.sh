#!/bin/bash
# Pre-task setup for Audit Outpatient Prescriptions task

echo "=== Setting up Audit Outpatient Prescriptions Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Fallback for screenshot function
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

# -----------------------------------------------------------------------------
# DATA CHECK: Ensure there is at least one prescription with refills
# -----------------------------------------------------------------------------
echo "Checking for prescriptions with refills in ^PSRX..."
# M command: Iterate ^PSRX, check if node 1 (refill) exists. Return first match.
# Command logic: S X=0 F  S X=$O(^PSRX(X)) Q:'X  I $D(^PSRX(X,1)) W X Q
SAMPLE_RX_IEN=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S X=0 F  S X=\$O(^PSRX(X)) Q:X=\"\"  I \$D(^PSRX(X,1)) W X Q"' 2>/dev/null | tail -1)

if [ -n "$SAMPLE_RX_IEN" ] && [ "$SAMPLE_RX_IEN" != "" ]; then
    echo "Found sample prescription with refills: IEN $SAMPLE_RX_IEN"
    echo "$SAMPLE_RX_IEN" > /tmp/target_rx_ien.txt
else
    echo "WARNING: No prescriptions with refills found. Attempting to locate any prescription..."
    SAMPLE_RX_IEN=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^PSRX(0))"' 2>/dev/null | tail -1)
    echo "Fallback prescription IEN: $SAMPLE_RX_IEN"
fi

# -----------------------------------------------------------------------------
# WEB INTERFACE SETUP
# -----------------------------------------------------------------------------

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
        # Activate and maximize
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 5
# Dismiss potential popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Audit outpatient prescription refill records"
echo "Target Global: ^PSRX"
if [ -n "$SAMPLE_RX_IEN" ]; then
    echo "Hint: Prescription IEN $SAMPLE_RX_IEN has data."
fi
echo ""