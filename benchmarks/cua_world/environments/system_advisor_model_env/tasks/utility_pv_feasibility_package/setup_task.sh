#!/bin/bash
echo "=== Setting up utility_pv_feasibility_package task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/phoenix_feasibility_package.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time (AFTER cleaning so timestamps are correct)
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Verify Phoenix weather file is available
PHOENIX_FILE="/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
if [ ! -f "$PHOENIX_FILE" ]; then
    echo "WARNING: Phoenix weather file not found at $PHOENIX_FILE"
    # Try to find it in SAM's bundled resources
    SAM_SOLAR_DIR=$(cat /home/ga/.SAM/solar_resource_dir.txt 2>/dev/null || echo "")
    if [ -n "$SAM_SOLAR_DIR" ]; then
        ALT_FILE=$(find "$SAM_SOLAR_DIR" -iname "*phoenix*" 2>/dev/null | head -n 1)
        if [ -n "$ALT_FILE" ]; then
            echo "Found alternative Phoenix file: $ALT_FILE"
            mkdir -p /home/ga/SAM_Weather_Data
            cp "$ALT_FILE" "$PHOENIX_FILE"
            chown ga:ga "$PHOENIX_FILE"
        fi
    fi
fi

# Ensure weather file path hint exists
mkdir -p /home/ga/.SAM
echo "$PHOENIX_FILE" > /home/ga/.SAM/weather_file_for_task.txt
chown -R ga:ga /home/ga/.SAM

# Ensure a terminal is available for the agent to write and run PySAM scripts
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="
