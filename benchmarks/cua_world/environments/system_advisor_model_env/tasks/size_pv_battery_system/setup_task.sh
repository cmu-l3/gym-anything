#!/bin/bash
echo "=== Setting up size_pv_battery_system task ==="

# Clean pre-existing files
rm -f /home/ga/Documents/SAM_Projects/pv_battery_report.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py 2>/dev/null || true

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure solar resource text file exists and is populated
if [ ! -f "/home/ga/.SAM/solar_resource_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt 2>/dev/null || echo "/opt/SAM/current")
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
    if [ -n "$SOLAR_RES" ]; then
        mkdir -p /home/ga/.SAM
        echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
        chown -R ga:ga /home/ga/.SAM
    fi
fi

# Record task start time (anti-gaming)
date +%s > /home/ga/.task_start_time

# Start terminal for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="