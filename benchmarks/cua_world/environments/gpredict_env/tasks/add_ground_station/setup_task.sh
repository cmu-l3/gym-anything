#!/bin/bash
echo "=== Setting up add_ground_station task ==="

GPREDICT_CONF_DIR="/home/ga/.config/Gpredict"

# Ensure no Tokyo.qth exists already (clean start)
rm -f "${GPREDICT_CONF_DIR}/Tokyo.qth" 2>/dev/null || true

# Kill any existing GPredict instance
pkill -x gpredict || true
sleep 2

# Launch GPredict
echo "Launching GPredict..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority setsid gpredict > /tmp/gpredict_task.log 2>&1 &"
sleep 5

# Wait for GPredict window to appear
TIMEOUT=30
ELAPSED=0
WID=""
while [ $ELAPSED -lt $TIMEOUT ]; do
    WID=$(DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool search --name "Gpredict" 2>/dev/null | head -1) || true
    if [ -n "$WID" ]; then
        echo "GPredict window found (WID: $WID)"
        break
    fi
    sleep 2
    ELAPSED=$((ELAPSED + 2))
done

if [ -z "$WID" ]; then
    echo "WARNING: GPredict window not found after ${TIMEOUT}s"
    echo "GPredict log:"
    cat /tmp/gpredict_task.log 2>/dev/null || true
else
    # Maximize the window (run as ga user for X access)
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority wmctrl -r 'Gpredict' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
    sleep 1
    # Dismiss any dialogs
    su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority xdotool key Escape" 2>/dev/null || true
    sleep 1
fi

echo "=== add_ground_station task setup complete ==="


