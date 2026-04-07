#!/bin/bash
set -e
echo "=== Setting up record_synthetic_session task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# 1. Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt
echo "Task start time: $(cat /tmp/task_start_time.txt)"

# 2. Prepare Recordings directory
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
su - ga -c "mkdir -p '$RECORDINGS_DIR'"

# 3. Snapshot existing sessions to differentiate new ones later
ls -1 "$RECORDINGS_DIR" > /tmp/initial_recordings_list.txt 2>/dev/null || touch /tmp/initial_recordings_list.txt
echo "Existing recording directories: $(wc -l < /tmp/initial_recordings_list.txt)"

# 4. Launch OpenBCI GUI (if not already running)
# We want to start at the Control Panel (System Control Panel)
if pgrep -f "OpenBCI_GUI" > /dev/null; then
    echo "OpenBCI GUI is already running. Killing to ensure fresh start at Control Panel..."
    pkill -f "OpenBCI_GUI" 2>/dev/null || true
    sleep 2
fi

echo "Launching OpenBCI GUI..."
# Use the utility function if available, otherwise manual launch
if command -v launch_openbci >/dev/null 2>&1; then
    launch_openbci
else
    # Fallback manual launch
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
        bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"
    
    # Wait for window
    for i in {1..45}; do
        if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "openbci" > /dev/null; then
            echo "Window appeared."
            break
        fi
        sleep 1
    done
fi

# 5. Ensure window is maximized and focused
sleep 2
WID=$(DISPLAY=:1 wmctrl -l | grep -i "openbci" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    echo "Maximizing window $WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz
    DISPLAY=:1 wmctrl -i -a "$WID"
fi

# 6. Take initial screenshot
if command -v take_screenshot >/dev/null 2>&1; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="