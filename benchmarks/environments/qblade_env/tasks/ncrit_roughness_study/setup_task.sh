#!/bin/bash
set -e
echo "=== Setting up Ncrit roughness study task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/projects
chown -R ga:ga /home/ga/Documents/

# Clean up any previous results to ensure fresh start
rm -f /home/ga/Documents/roughness_study_results.txt 2>/dev/null || true
rm -f /home/ga/Documents/projects/roughness_study.wpa 2>/dev/null || true

# Kill any existing QBlade instances
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade
echo "Launching QBlade..."
# Use the launch script if available, otherwise direct
if [ -f "/home/ga/Desktop/launch_qblade.sh" ]; then
    su - ga -c "/home/ga/Desktop/launch_qblade.sh > /tmp/qblade.log 2>&1 &"
else
    # Fallback logic to find binary
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade.log 2>&1 &"
    fi
fi

# Wait for QBlade window
echo "Waiting for QBlade window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "qblade" > /dev/null; then
        echo "QBlade window detected."
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Ncrit roughness study task setup complete ==="