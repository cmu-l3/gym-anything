#!/bin/bash
set -e

echo "=== Setting up run_dms_vawt_simulation task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/projects
chown ga:ga /home/ga/Documents/projects

# Clean up previous task artifacts
rm -f /home/ga/Documents/projects/vawt_dms_result.wpa 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Find a suitable VAWT sample project
# QBlade usually ships with "VAWT_Test.wpa" or similar in sample projects
SAMPLE_DIR="/home/ga/Documents/sample_projects"
VAWT_PROJECT=$(find "$SAMPLE_DIR" -iname "*vawt*.wpa" -o -iname "*darrieus*.wpa" | head -n 1)

# Fallback: if no specific VAWT project found, take the largest WPA file (likely contains data)
if [ -z "$VAWT_PROJECT" ]; then
    VAWT_PROJECT=$(find "$SAMPLE_DIR" -name "*.wpa" -type f -printf "%s %p\n" | sort -nr | head -n 1 | awk '{print $2}')
fi

if [ -z "$VAWT_PROJECT" ]; then
    echo "ERROR: No sample project found in $SAMPLE_DIR"
    exit 1
fi

echo "Selected project: $VAWT_PROJECT"

# Helper to find QBlade binary
find_qblade_binary() {
    local QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f -executable 2>/dev/null | head -1)
    if [ -z "$QBLADE_BIN" ]; then
        QBLADE_BIN=$(find /opt/qblade -name "QBlade*" -type f 2>/dev/null | grep -iv '\.txt\|\.pdf\|\.md\|\.dll' | head -1)
    fi
    echo "$QBLADE_BIN"
}

QBLADE_BIN=$(find_qblade_binary)
QBLADE_DIR=$(dirname "$QBLADE_BIN")

# Start QBlade with the project loaded
echo "Starting QBlade..."
if ! pgrep -f "QBlade" > /dev/null; then
    su - ga -c "export DISPLAY=:1; export LD_LIBRARY_PATH='$QBLADE_DIR':\${LD_LIBRARY_PATH:-}; cd '$QBLADE_DIR' && '$QBLADE_BIN' '$VAWT_PROJECT' > /tmp/qblade_task.log 2>&1 &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "QBlade"; then
        echo "QBlade window detected"
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r "QBlade" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Focus the window
DISPLAY=:1 wmctrl -a "QBlade" 2>/dev/null || true

# Dismiss potential startup dialogs (like "Welcome" or "Update")
sleep 2
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="