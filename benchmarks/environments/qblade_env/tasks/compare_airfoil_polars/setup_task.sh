#!/bin/bash
set -e
echo "=== Setting up compare_airfoil_polars task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/projects
rm -f /home/ga/Documents/projects/airfoil_comparison.wpa 2>/dev/null || true
chown -R ga:ga /home/ga/Documents/projects

# Kill any existing QBlade instances for clean start
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade
echo "Launching QBlade..."
# Use shared launch function if available, otherwise direct launch
if type launch_qblade &>/dev/null; then
    launch_qblade
else
    # Fallback launch logic
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade_task.log 2>&1 &"
    fi
fi
sleep 5

# Wait for QBlade window to appear
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
        echo "QBlade window detected"
        break
    fi
    sleep 1
done

# Maximize and focus the QBlade window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Dismiss any startup dialogs
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="