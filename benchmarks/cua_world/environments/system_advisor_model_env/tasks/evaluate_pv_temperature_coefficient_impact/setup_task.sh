#!/bin/bash
echo "=== Setting up evaluate_pv_temperature_coefficient_impact task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/temp_coef_comparison.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Make sure the weather data file exists
if [ ! -f "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" ]; then
    echo "WARNING: Weather data file not found at expected location"
    # Try to find it and link it
    SAM_DIR=""
    if [ -f "/opt/SAM/sam_dir.txt" ]; then
        SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
        WEATHER_FOUND=$(find "$SAM_DIR" -name "*phoenix*" -o -name "*Phoenix*" 2>/dev/null | head -1)
        if [ -n "$WEATHER_FOUND" ]; then
            mkdir -p /home/ga/SAM_Weather_Data
            cp "$WEATHER_FOUND" "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" 2>/dev/null || true
        fi
    fi
fi
chown -R ga:ga /home/ga/SAM_Weather_Data 2>/dev/null || true

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="