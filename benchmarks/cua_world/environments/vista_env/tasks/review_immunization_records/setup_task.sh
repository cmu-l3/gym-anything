#!/bin/bash
# Pre-task setup for Review Immunization Records task

echo "=== Setting up Review Immunization Records Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

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
# Verify Data Existence (Ground Truth)
# -----------------------------------------------------------------------------
echo "Checking Immunization data..."

# Check ^AUTNIMM (Immunization Types)
AUTNIMM_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^AUTNIMM(0))"' 2>/dev/null | tail -1)
if [ -n "$AUTNIMM_CHECK" ]; then
    echo "  ^AUTNIMM (Types) exists: YES"
    echo "true" > /tmp/autnimm_exists
else
    echo "  ^AUTNIMM (Types) exists: NO (Warning)"
    echo "false" > /tmp/autnimm_exists
fi

# Check ^AUPNVIMM (Vaccination Events)
AUPNVIMM_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^AUPNVIMM(0))"' 2>/dev/null | tail -1)
if [ -n "$AUPNVIMM_CHECK" ]; then
    echo "  ^AUPNVIMM (Events) exists: YES"
    echo "true" > /tmp/aupnvimm_exists
else
    echo "  ^AUPNVIMM (Events) exists: NO (Warning)"
    echo "false" > /tmp/aupnvimm_exists
fi

# Get sample vaccine names for verification reference (first 5)
echo "Fetching sample vaccine names..."
SAMPLE_VACCINES=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "S U=\"^\",X=0,N=0 F  S X=\$O(^AUTNIMM(X)) Q:X=\"\"!(N>=5)  S N=N+1 W \$P(\$G(^AUTNIMM(X,0)),U,1),\",\""' 2>/dev/null | tail -1)
echo "  Samples: $SAMPLE_VACCINES"
echo "$SAMPLE_VACCINES" > /tmp/sample_vaccines.txt

# -----------------------------------------------------------------------------
# Web Interface Setup
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
        DISPLAY=:1 wmctrl -ia "$WID" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

sleep 5
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

take_screenshot /tmp/task_initial_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Navigate to ^AUTNIMM and ^AUPNVIMM to view immunization data"
echo ""