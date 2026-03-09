#!/bin/bash
set -e
echo "=== Setting up Rotor Correction Model Study task ==="

# Source shared utilities
source /workspace/scripts/task_utils.sh 2>/dev/null || true

# 1. Clean up previous artifacts to ensure a fresh start
rm -f /home/ga/Documents/tip_loss_report.txt 2>/dev/null || true
rm -f /home/ga/Documents/projects/tip_loss_study.wpa 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# 2. Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# 3. Ensure QBlade is running and ready
if ! pgrep -f "QBlade" > /dev/null; then
    echo "Launching QBlade..."
    # Launch logic tailored to the environment
    QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -z "$QBLADE_BIN" ]; then
         QBLADE_BIN="QBlade" # Fallback to path
    fi
    
    QBLADE_DIR=$(dirname "$QBLADE_BIN")
    su - ga -c "export DISPLAY=:1; cd '$QBLADE_DIR' && '$QBLADE_BIN' > /tmp/qblade.log 2>&1 &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
            echo "QBlade window detected."
            break
        fi
        sleep 1
    done
fi

# 4. Maximize window for visibility
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# 5. Capture initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="