#!/bin/bash
# Pre-task setup for Cross-System Patient Data Completeness task

echo "=== Setting up Cross-System Patient Data Completeness Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Record task start time
date +%s > /tmp/task_start_timestamp
echo "Task start timestamp: $(cat /tmp/task_start_timestamp)"

# Get container IP
CONTAINER_IP=$(cat /tmp/vista_container_ip 2>/dev/null)
if [ -z "$CONTAINER_IP" ]; then
    CONTAINER_IP=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' vista-vehu 2>/dev/null)
    echo "$CONTAINER_IP" > /tmp/vista_container_ip
fi
echo "VistA Container IP: $CONTAINER_IP"

# Verify VistA container is running
if ! docker ps --filter "name=vista-vehu" --filter "status=running" -q 2>/dev/null | head -1 | grep -q .; then
    echo "ERROR: VistA container not running!"
    exit 1
fi
echo "VistA container: RUNNING"

# Verify all four clinical globals have data
echo "Verifying all clinical globals have data..."

FIRST_PS=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W $O(^PS(55,0))"' 2>/dev/null | tail -1)
echo "  ^PS(55) first DFN: ${FIRST_PS:-NONE}"

FIRST_GMR=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W $O(^GMR(120.5,0))"' 2>/dev/null | tail -1)
echo "  ^GMR(120.5) first IEN: ${FIRST_GMR:-NONE}"

FIRST_GMRD=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W $O(^GMRD(120.8,0))"' 2>/dev/null | tail -1)
echo "  ^GMRD(120.8) first IEN: ${FIRST_GMRD:-NONE}"

FIRST_PROB=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W $O(^AUPNPROB(0))"' 2>/dev/null | tail -1)
echo "  ^AUPNPROB first IEN: ${FIRST_PROB:-NONE}"

FIRST_DPT=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W $O(^DPT(0))"' 2>/dev/null | tail -1)
echo "  ^DPT first DFN: ${FIRST_DPT:-NONE}"

# Ensure YDBGui is running
echo "Checking YDBGui status..."
YDBGUI_RUNNING=$(docker exec vista-vehu ps aux 2>/dev/null | grep -i ydbgui | grep -v grep)
if [ -z "$YDBGUI_RUNNING" ]; then
    echo "Starting YDBGui..."
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

# Remove any stale output file
rm -f /home/ga/Desktop/patient_profile.txt 2>/dev/null || true

# Kill existing Firefox and launch fresh
pkill -9 firefox 2>/dev/null || true
sleep 1

echo "Launching Firefox with YDBGui..."
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

take_screenshot /tmp/task_start_screenshot.png

echo ""
echo "=== Setup Complete ==="
echo "Task: Find patient with highest composite data volume across 4 VistA globals"
echo "Globals: ^PS(55) + ^GMR(120.5) + ^GMRD(120.8) + ^AUPNPROB + ^DPT"
echo "Output file: /home/ga/Desktop/patient_profile.txt"
echo ""
