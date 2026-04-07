#!/bin/bash
set -e
echo "=== Setting up insert_event_markers task ==="

# Source shared utilities if available
if [ -f "/home/ga/openbci_task_utils.sh" ]; then
    source /home/ga/openbci_task_utils.sh
fi

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt
echo "Task start time recorded: $(cat /tmp/task_start_time.txt)"

# Record the list of existing recording files to distinguish new ones later
RECORDINGS_DIR="/home/ga/Documents/OpenBCI_GUI/Recordings"
mkdir -p "$RECORDINGS_DIR"
ls -1 "$RECORDINGS_DIR" > /tmp/existing_recordings.txt 2>/dev/null || touch /tmp/existing_recordings.txt

# Launch OpenBCI GUI to the System Control Panel
# The agent is expected to select Synthetic mode themselves
echo "Launching OpenBCI GUI..."
pkill -f "OpenBCI_GUI" 2>/dev/null || true

# Use the wrapper or launch script
if [ -f "/home/ga/launch_openbci.sh" ]; then
    su - ga -c "setsid DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority bash /home/ga/launch_openbci.sh > /tmp/openbci_launch.log 2>&1 &"
else
    # Fallback to direct launch if wrapper missing
    OPENBCI_EXEC=$(cat /opt/openbci_exec_path.txt 2>/dev/null || which openbci_gui)
    OPENBCI_BASE=$(cat /opt/openbci_base_dir.txt 2>/dev/null || dirname "$OPENBCI_EXEC")
    if [ -n "$OPENBCI_EXEC" ]; then
        cd "$OPENBCI_BASE"
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/run/user/1000/gdm/Xauthority; setsid \"$OPENBCI_EXEC\" > /tmp/openbci_launch.log 2>&1 &"
    fi
fi

# Wait for window
echo "Waiting for OpenBCI GUI window..."
for i in {1..45}; do
    if DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -l 2>/dev/null | grep -i "openbci" >/dev/null; then
        echo "Window detected."
        break
    fi
    sleep 1
done

# Ensure window is maximized
DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority wmctrl -r "OpenBCI" -b add,maximized_vert,maximized_horz 2>/dev/null || true
sleep 2

# Take initial screenshot
if type take_screenshot >/dev/null 2>&1; then
    take_screenshot /tmp/task_initial.png
else
    DISPLAY=:1 XAUTHORITY=/run/user/1000/gdm/Xauthority scrot /tmp/task_initial.png 2>/dev/null || true
fi

echo "=== Task setup complete ==="