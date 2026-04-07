#!/bin/bash
# Pre-task setup for High-Risk Patient Clinical Dossier task

echo "=== Setting up High-Risk Patient Clinical Dossier Task ==="

source /workspace/scripts/task_utils.sh 2>/dev/null || true

if ! type take_screenshot &>/dev/null; then
    take_screenshot() {
        local path="${1:-/tmp/screenshot.png}"
        DISPLAY=:1 import -window root "$path" 2>/dev/null || true
    }
fi

# Remove any stale output file BEFORE recording timestamp
rm -f /home/ga/Desktop/patient_risk_dossier.txt 2>/dev/null || true

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

# Verify all required globals have data
echo "Verifying required database globals..."

FIRST_PS=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^PS(55,0))"' 2>/dev/null | tail -1)
echo "  ^PS(55) first DFN: ${FIRST_PS:-NONE}"

FIRST_GMRD=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^GMRD(120.8,0))"' 2>/dev/null | tail -1)
echo "  ^GMR(120.8) first IEN: ${FIRST_GMRD:-NONE}"

FIRST_DPT=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^DPT(0))"' 2>/dev/null | tail -1)
echo "  ^DPT first DFN: ${FIRST_DPT:-NONE}"

DIC21_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DIC(21,0))"' 2>/dev/null | tail -1)
echo "  ^DIC(21) exists: ${DIC21_CHECK:-0}"

DIC8_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DIC(8,0))"' 2>/dev/null | tail -1)
echo "  ^DIC(8) exists: ${DIC8_CHECK:-0}"

DIC31_CHECK=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$D(^DIC(31,0))"' 2>/dev/null | tail -1)
echo "  ^DIC(31) exists: ${DIC31_CHECK:-0}"

FIRST_PSRX=$(docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && yottadb -run %XCMD "W \$O(^PSRX(0))"' 2>/dev/null | tail -1)
echo "  ^PSRX first IEN: ${FIRST_PSRX:-NONE}"

# Restart YDBGui WITHOUT authentication
# The cached post_start state may have YDBGui running with --auth-file.
# We must kill it and restart without the auth flag.
echo "Restarting YDBGui without authentication..."
docker exec vista-vehu pkill -f ydbgui 2>/dev/null || true
sleep 3

# Start YDBGui without --auth-file (no login required)
docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 --readwrite > /home/vehu/log/ydbgui-noauth.log 2>&1 &'
sleep 5

# Verify YDBGui is accessible and does NOT require auth
for i in {1..30}; do
    HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" "http://${CONTAINER_IP}:8089/" 2>/dev/null)
    if [ "$HTTP_CODE" = "200" ]; then
        echo "YDBGui is accessible (no auth)"
        break
    fi
    sleep 1
done

# Confirm no auth-file in process
YDBGUI_PROC=$(docker exec vista-vehu ps aux 2>/dev/null | grep ydbgui | grep -v grep)
echo "YDBGui process: $YDBGUI_PROC"
if echo "$YDBGUI_PROC" | grep -q "auth-file"; then
    echo "WARNING: YDBGui still running with auth-file, retrying..."
    docker exec vista-vehu pkill -f ydbgui 2>/dev/null || true
    sleep 3
    docker exec -u vehu vista-vehu bash -c 'source /home/vehu/etc/env && nohup yottadb -run %ydbgui --port 8089 --readwrite > /home/vehu/log/ydbgui-noauth.log 2>&1 &'
    sleep 5
fi

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
echo "Task: Identify highest medication-allergy risk patient and compile clinical dossier"
echo "Required globals: ^PS(55), ^GMR(120.8), ^DPT, ^DIC(21), ^DIC(8), ^DIC(31), ^PSRX"
echo "Output file: /home/ga/Desktop/patient_risk_dossier.txt"
echo ""
