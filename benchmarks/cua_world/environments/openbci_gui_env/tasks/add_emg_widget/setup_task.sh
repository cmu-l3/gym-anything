#!/bin/bash
set -e
echo "=== Setting up add_emg_widget task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
else
    echo "WARNING: openbci_task_utils.sh not found, defining minimal fallbacks"
    take_screenshot() {
        DISPLAY=:1 scrot "$1" 2>/dev/null || true
    }
fi

# Record task start time
date +%s > /tmp/task_start_time.txt

# 1. CLEANUP: Reset OpenBCI Settings to ensure no EMG widget exists from previous runs
# OpenBCI stores layout in Documents/OpenBCI_GUI/Settings
echo "Resetting OpenBCI GUI layout to defaults..."
rm -rf /home/ga/Documents/OpenBCI_GUI/Settings/* 2>/dev/null || true
# Re-create directory structure to be safe
mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings

# 2. LAUNCH: Start OpenBCI GUI
echo "Launching OpenBCI GUI..."
# Kill any existing instances
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch in background
su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority \
    bash /home/ga/launch_openbci.sh > /tmp/openbci_task_launch.log 2>&1 &"

# 3. WAIT: Wait for the System Control Panel to appear
echo "Waiting for OpenBCI GUI window..."
GUI_READY=0
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "OpenBCI" > /dev/null; then
        echo "Window detected."
        GUI_READY=1
        break
    fi
    sleep 1
done

if [ "$GUI_READY" -eq 0 ]; then
    echo "ERROR: OpenBCI GUI failed to start."
    exit 1
fi

# 4. PREPARE: Maximize window
sleep 3
DISPLAY=:1 wmctrl -r "OpenBCI_GUI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
# Focus window
DISPLAY=:1 wmctrl -a "OpenBCI_GUI" 2>/dev/null || true

# 5. EVIDENCE: Initial screenshot
take_screenshot /tmp/task_initial.png

echo "=== Task setup complete ==="
echo "State: OpenBCI GUI launched at System Control Panel (Default Layout reset)"