#!/bin/bash
set -e
echo "=== Setting up extract_waveforms_scart task ==="

source /workspace/scripts/task_utils.sh

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Clean up any existing output from previous runs
rm -f /home/ga/extracted_BKB_BHZ.mseed

# Verify that the SDS archive contains the necessary data (sanity check)
SDS_CHECK="/home/ga/seiscomp/var/lib/archive/2024/GE/BKB"
if [ ! -d "$SDS_CHECK" ]; then
    echo "WARNING: SDS archive for GE.BKB not found at $SDS_CHECK. Check environment configuration."
fi

# Close any existing terminals to ensure a clean state
pkill -f "gnome-terminal" 2>/dev/null || true
sleep 1

# Launch a fresh, maximized terminal for the agent
echo "Launching terminal..."
su - ga -c "DISPLAY=:1 XAUTHORITY=/home/ga/.Xauthority gnome-terminal --maximize -- bash -l" &
sleep 4

# Focus the terminal
WID=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "terminal" | head -1 | awk '{print $1}')
if [ -n "$WID" ]; then
    DISPLAY=:1 wmctrl -i -a "$WID"
    DISPLAY=:1 wmctrl -i -r "$WID" -b add,maximized_vert,maximized_horz 2>/dev/null || true
fi

# Allow UI to stabilize
sleep 1

# Take an initial state screenshot proving the terminal is open and ready
take_screenshot /tmp/task_initial.png

# Verify screenshot was captured
if [ -f /tmp/task_initial.png ]; then
    SIZE=$(stat -c %s /tmp/task_initial.png 2>/dev/null || echo "0")
    echo "Initial screenshot captured: ${SIZE} bytes"
else
    echo "WARNING: Could not capture initial screenshot"
fi

echo "=== Task setup complete ==="