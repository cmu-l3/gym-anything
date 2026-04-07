#!/bin/bash
echo "=== Setting up Evaluate DC/AC Ratio Impact Task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Remove any previous result file (clean state)
rm -f /home/ga/Documents/SAM_Projects/dcac_ratio_comparison.json
rm -f /home/ga/Documents/SAM_Projects/*.py
rm -f /home/ga/*.py

# Verify solar_resource directory is recorded and accessible
SOLAR_RES_FILE="/home/ga/.SAM/solar_resource_dir.txt"
if [ ! -f "$SOLAR_RES_FILE" ]; then
    echo "WARNING: solar_resource_dir.txt not found, searching..."
    SAM_DIR=""
    if [ -f "/opt/SAM/sam_dir.txt" ]; then
        SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
    fi
    if [ -n "$SAM_DIR" ]; then
        SOLAR_DIR=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
        if [ -n "$SOLAR_DIR" ]; then
            mkdir -p /home/ga/.SAM
            echo "$SOLAR_DIR" > "$SOLAR_RES_FILE"
            chown -R ga:ga /home/ga/.SAM
            echo "Found and recorded solar_resource directory: $SOLAR_DIR"
        fi
    fi
fi

# Kill SAM GUI if running (not needed for this scripting task)
killall -9 sam sam.bin SAM 2>/dev/null || true
sleep 1

# Open a terminal for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || DISPLAY=:1 wmctrl -a "terminal" 2>/dev/null || true
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="