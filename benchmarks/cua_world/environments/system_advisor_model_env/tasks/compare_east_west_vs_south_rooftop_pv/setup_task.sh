#!/bin/bash
echo "=== Setting up compare_east_west_vs_south_rooftop_pv task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/rooftop_layout_comparison.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python scripts from previous task runs to ensure clean slate
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time for anti-gaming file modification checks
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists and belongs to the correct user
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure the weather data is available
if [ ! -f "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" ]; then
    echo "WARNING: Weather data missing. Creating a placeholder to prevent instant crash."
    mkdir -p /home/ga/SAM_Weather_Data
    touch /home/ga/SAM_Weather_Data/phoenix_az_tmy.csv
    chown -R ga:ga /home/ga/SAM_Weather_Data
fi

# Ensure a terminal is available for the agent to write its scripts
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take an initial screenshot to confirm the setup state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="