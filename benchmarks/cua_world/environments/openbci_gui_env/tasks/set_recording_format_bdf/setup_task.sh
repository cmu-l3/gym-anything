#!/bin/bash
set -e
echo "=== Setting up set_recording_format_bdf task ==="

# Source shared utilities
source /home/ga/openbci_task_utils.sh 2>/dev/null || true

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Record initial state of recordings directory
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"

# Clean up any previous BDF files to avoid confusion (optional, but cleaner)
# We won't delete them to simulate a real user env, but we will count them.
find "$RECORDINGS_DIR" -name "*.bdf" -type f 2>/dev/null | wc -l > /tmp/initial_bdf_count.txt

# Kill any existing OpenBCI GUI instance
pkill -f "OpenBCI_GUI" 2>/dev/null || true
sleep 2

# Launch OpenBCI GUI
echo "Launching OpenBCI GUI..."
# We use the wrapper script which handles paths correctly
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; \
    setsid bash /home/ga/launch_openbci.sh > /tmp/openbci_task.log 2>&1 &"

# Wait for GUI window
echo "Waiting for OpenBCI GUI window..."
wait_for_openbci 60 || {
    echo "ERROR: OpenBCI GUI did not start within 60s"
    exit 1
}

sleep 5

# Maximize the window
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 1

# Dismiss any startup dialogs (Checking for updates, etc)
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority xdotool key Escape 2>/dev/null || true
sleep 1

# Take screenshot of initial state
take_screenshot /tmp/task_initial_state.png

echo "=== Task setup complete ==="
echo "OpenBCI GUI is running on the System Control Panel."
echo "Task start time: $(cat /tmp/task_start_time.txt)"