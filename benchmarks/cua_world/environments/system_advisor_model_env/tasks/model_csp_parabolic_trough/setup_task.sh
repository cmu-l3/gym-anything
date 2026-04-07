#!/bin/bash
echo "=== Setting up CSP Parabolic Trough task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt
# Alternatively, create a reference file
touch /tmp/task_start_marker

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents

# Remove any previous task artifacts to ensure clean state
rm -f /home/ga/Documents/SAM_Projects/csp_trough_report.json
rm -f /home/ga/Documents/SAM_Projects/csp_trough_simulation.py

# Verify PySAM is available
if ! python3 -c "import PySAM.TroughPhysical" 2>/dev/null; then
    echo "WARNING: PySAM TroughPhysical not immediately available. Agent may need to discover proper imports."
fi

# Make sure the SAM weather resource dir hint is available
if [ ! -f /home/ga/.SAM/solar_resource_dir.txt ]; then
    mkdir -p /home/ga/.SAM
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt 2>/dev/null || echo "")
    if [ -n "$SAM_DIR" ]; then
        SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
        if [ -n "$SOLAR_RES" ]; then
            echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
            chown -R ga:ga /home/ga/.SAM
        fi
    fi
fi

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== CSP Parabolic Trough task setup complete ==="