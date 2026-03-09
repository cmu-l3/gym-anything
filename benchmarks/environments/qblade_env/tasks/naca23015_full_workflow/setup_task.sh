#!/bin/bash
set -e
echo "=== Setting up NACA 23015 Full Workflow task ==="

# Source shared utilities if available
if [ -f "/workspace/scripts/task_utils.sh" ]; then
    source /workspace/scripts/task_utils.sh
fi

# 1. Anti-gaming: Record start time
date +%s > /tmp/task_start_time.txt

# 2. Environment Prep: Clean output directory
PROJECT_DIR="/home/ga/Documents/projects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Remove the target file if it exists to ensure fresh creation
rm -f "$PROJECT_DIR/naca23015_analysis.wpa" 2>/dev/null || true

# 3. Launch QBlade
echo "Launching QBlade..."
# Use task_utils launcher if available, otherwise manual launch
if type launch_qblade &>/dev/null; then
    launch_qblade
else
    # Manual fallback
    pkill -f "QBlade" 2>/dev/null || true
    sleep 1
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -n "$QBLADE_BIN" ]; then
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade_task.log 2>&1 &"
    fi
fi

# 4. Wait for window and maximize
echo "Waiting for QBlade window..."
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
        echo "Window found."
        break
    fi
    sleep 1
done
sleep 2

# Maximize (Critical for VLM visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 5. Capture Initial State Screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="