#!/bin/bash
set -e
echo "=== Setting up Multi-Airfoil Blade Design Task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Ensure output directory exists and is clean
PROJECT_DIR="/home/ga/Documents/projects"
mkdir -p "$PROJECT_DIR"
chown ga:ga "$PROJECT_DIR"

# Remove any pre-existing target file to prevent false positives
rm -f "$PROJECT_DIR/multi_airfoil_blade.wpa"

# 3. Launch QBlade if not running
if ! pgrep -f "QBlade" > /dev/null; then
    echo "Starting QBlade..."
    # Use the launch function from task_utils if available, else manual
    if type launch_qblade &>/dev/null; then
        launch_qblade
    else
        # Fallback manual launch
        QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable | head -1)
        QBLADE_DIR=$(dirname "$QBLADE_BIN")
        su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR'; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /dev/null 2>&1 &"
    fi
    sleep 8
fi

# 4. Wait for window and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
        echo "QBlade window detected"
        break
    fi
    sleep 1
done

# Maximize the window (CRITICAL for agent visibility)
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 5. Dismiss any potential "Tip of the day" or startup popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 0.5

# 6. Take initial state screenshot
take_screenshot /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="