#!/bin/bash
set -e
echo "=== Setting up configure_timeseries_scale task ==="

# 1. Record task start time for anti-gaming (file timestamp checks)
date +%s > /tmp/task_start_time.txt

# 2. Clean up previous state
# Kill any existing OpenBCI instances
pkill -f "OpenBCI_GUI" 2>/dev/null || true
pkill -f "java" 2>/dev/null || true
sleep 2

# Remove the target screenshot if it exists from a previous run
rm -f "/home/ga/Documents/OpenBCI_GUI/Screenshots/timeseries_config.png"

# 3. Launch OpenBCI GUI
# Using the wrapper or direct executable
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "DISPLAY=:1 /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"
else
    # Fallback if launch script is missing
    OPENBCI_EXEC=$(cat /opt/openbci_exec_path.txt 2>/dev/null || echo "OpenBCI_GUI")
    OPENBCI_BASE=$(cat /opt/openbci_base_dir.txt 2>/dev/null || echo "/opt/openbci_gui")
    cd "$OPENBCI_BASE"
    su - ga -c "DISPLAY=:1 ./OpenBCI_GUI > /tmp/openbci_launch.log 2>&1 &"
fi

# 4. Wait for window to appear
echo "Waiting for OpenBCI GUI..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "openbci" > /dev/null; then
        echo "OpenBCI GUI window detected."
        break
    fi
    sleep 1
done

# 5. Maximize and focus the window
echo "Configuring window..."
sleep 2 # Wait for window to fully map
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# 6. Capture initial state screenshot
echo "Capturing initial state..."
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="