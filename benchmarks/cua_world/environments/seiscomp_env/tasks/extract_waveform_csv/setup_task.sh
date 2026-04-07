#!/bin/bash
echo "=== Setting up extract_waveform_csv task ==="

source /workspace/scripts/task_utils.sh

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

# Clean up any potential previous task attempts
rm -f /home/ga/toli_waveform.csv
rm -f /home/ga/*.py

# Ensure SeisComP services are running (though not strictly necessary for direct SDS access, good for environment consistency)
ensure_scmaster_running

# Verify the waveform data exists in the archive (bundling check)
ARCHIVE_DIR="$SEISCOMP_ROOT/var/lib/archive/2024/GE/TOLI/BHZ.D"
if [ ! -d "$ARCHIVE_DIR" ]; then
    echo "WARNING: Expected archive directory not found: $ARCHIVE_DIR"
fi

# Open a terminal for the agent to use
echo "Starting terminal..."
su - ga -c "DISPLAY=:1 gnome-terminal --maximize &" 2>/dev/null || su - ga -c "DISPLAY=:1 xterm -maximized &" 2>/dev/null || true

# Wait for terminal window
sleep 3
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="