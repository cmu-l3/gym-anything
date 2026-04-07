#!/bin/bash
echo "=== Setting up analyze_solar_resource_site task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/phoenix_site_assessment.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Make sure SAM is running (background)
if ! pgrep -f "sam" > /dev/null 2>&1; then
    if [ -f "/opt/SAM/sam_dir.txt" ]; then
        SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
        su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}:\$LD_LIBRARY_PATH' /usr/local/bin/sam > /tmp/sam_gui.log 2>&1 &"
        sleep 5
    fi
fi

# Ensure a terminal is available for the agent (since this is heavily Python-based)
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Take initial screenshot showing environment is ready
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="