#!/bin/bash
echo "=== Setting up replace_fft_with_head_plot task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time (for anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure OpenBCI GUI directories exist and are owned by ga
mkdir -p /home/ga/Documents/OpenBCI_GUI/Screenshots
mkdir -p /home/ga/Documents/OpenBCI_GUI/Settings
chown -R ga:ga /home/ga/Documents/OpenBCI_GUI

# Clean up any previous screenshots
rm -f /home/ga/Documents/OpenBCI_GUI/Screenshots/head_plot_layout.png

# Reset OpenBCI Settings to ensure default layout (which includes FFT)
# We delete the UserLayouts.json if it exists to force default
rm -f /home/ga/Documents/OpenBCI_GUI/Settings/UserLayouts.json

# Launch OpenBCI GUI
# We use the wrapper script if available, or call the executable directly
if [ -f "/home/ga/launch_openbci.sh" ]; then
    echo "Launching OpenBCI via wrapper..."
    su - ga -c "setsid /home/ga/launch_openbci.sh > /tmp/openbci.log 2>&1 &"
else
    echo "Launching OpenBCI via executable..."
    OPENBCI_EXEC=$(cat /opt/openbci_exec_path.txt 2>/dev/null)
    OPENBCI_BASE=$(cat /opt/openbci_base_dir.txt 2>/dev/null)
    if [ -n "$OPENBCI_EXEC" ]; then
        cd "$OPENBCI_BASE"
        su - ga -c "DISPLAY=:1 setsid \"$OPENBCI_EXEC\" > /tmp/openbci.log 2>&1 &"
    fi
fi

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 wmctrl -l | grep -i "OpenBCI"; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Maximize the window
sleep 2
DISPLAY=:1 wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "OpenBCI" 2>/dev/null || true

# Dismiss any potential "What's New" or "Welcome" popups by sending Escape
sleep 3
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="