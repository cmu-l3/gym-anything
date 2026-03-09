#!/bin/bash
set -e
echo "=== Setting up save_modified_project task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
rm -rf /home/ga/Documents/projects/*
mkdir -p /home/ga/Documents/projects/
chown -R ga:ga /home/ga/Documents/projects/

# Verify sample project exists
SAMPLE_PROJECT="/home/ga/Documents/sample_projects/Turbine Simulation.wpa"
if [ ! -f "$SAMPLE_PROJECT" ]; then
    echo "WARNING: Primary sample project not found at: $SAMPLE_PROJECT"
    # Try to find it in the QBlade install dir
    ALT_SAMPLE=$(find /opt/qblade -name "Turbine Simulation.wpa" -type f 2>/dev/null | head -1)
    if [ -n "$ALT_SAMPLE" ]; then
        echo "Found at: $ALT_SAMPLE"
        cp "$ALT_SAMPLE" "$SAMPLE_PROJECT"
    else
        echo "ERROR: Sample project 'Turbine Simulation.wpa' not found anywhere."
        exit 1
    fi
fi

# Record MD5 of original for anti-gaming comparison (to ensure file was actually modified)
md5sum "$SAMPLE_PROJECT" | awk '{print $1}' > /tmp/original_project_md5.txt
echo "Original project MD5: $(cat /tmp/original_project_md5.txt)"

# Kill any existing QBlade instances
pkill -f "[Qq][Bb]lade" 2>/dev/null || true
sleep 2

# Launch QBlade (empty, no project loaded)
# Using task_utils.sh launch function if available, otherwise direct
if type launch_qblade &>/dev/null; then
    launch_qblade
else
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    QBLADE_DIR=$(dirname "$QBLADE_BIN")
    su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade_task.log 2>&1 &"
fi

# Wait for QBlade window
sleep 5
for i in {1..40}; do
    if DISPLAY=:1 wmctrl -l | grep -i "qblade"; then
        echo "QBlade window detected"
        break
    fi
    sleep 1
done

# Maximize and focus QBlade window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="