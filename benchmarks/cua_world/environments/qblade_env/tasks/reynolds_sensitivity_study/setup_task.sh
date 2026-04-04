#!/bin/bash
set -e
echo "=== Setting up Reynolds Sensitivity Study Task ==="

# Source utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous artifacts
echo "Cleaning up previous runs..."
rm -f /home/ga/Documents/reynolds_study_report.txt
rm -f /home/ga/Documents/projects/reynolds_study.wpa
rm -f /tmp/task_result.json

# 3. Ensure S809 airfoil data exists
AIRFOIL_PATH="/home/ga/Documents/airfoils/s809.dat"
mkdir -p "$(dirname "$AIRFOIL_PATH")"

if [ ! -f "$AIRFOIL_PATH" ]; then
    echo "Restoring S809 airfoil data..."
    # Try copying from workspace data if available
    if [ -f "/workspace/data/airfoils/s809.dat" ]; then
        cp "/workspace/data/airfoils/s809.dat" "$AIRFOIL_PATH"
    else
        # Fallback: Create S809 data if missing (truncated for brevity, real task would use full file)
        # In a real env, we expect the install script to populate this, but we ensure it exists.
        # This is a placeholder check.
        echo "WARNING: s809.dat not found in source, checking standard locations..."
        FOUND=$(find /home/ga/Documents -name "s809.dat" | head -n 1)
        if [ -n "$FOUND" ]; then
             cp "$FOUND" "$AIRFOIL_PATH"
        else
             echo "ERROR: S809 airfoil file missing."
             exit 1
        fi
    fi
fi
chmod 644 "$AIRFOIL_PATH"
chown ga:ga "$AIRFOIL_PATH"

# 4. Launch QBlade
echo "Launching QBlade..."
# Assuming launch_qblade function exists in task_utils, otherwise explicit launch
if type launch_qblade &>/dev/null; then
    launch_qblade
else
    # Fallback launch
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade_task.log 2>&1 &"
    fi
fi

# 5. Wait for window and maximize
echo "Waiting for QBlade..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "qblade"; then
        echo "QBlade started."
        sleep 2
        DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# 6. Capture initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="