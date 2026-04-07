#!/bin/bash
echo "=== Setting up evaluate_pv_lcoe_lifetime_sensitivity task ==="

# Clean any pre-existing output files
rm -f /home/ga/Documents/SAM_Projects/lcoe_lifetime_sensitivity.json 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/lcoe_calculator.py 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Record task start time (for anti-gaming checks)
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Make sure Phoenix weather data is definitely accessible
if [ ! -f "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" ]; then
    mkdir -p /home/ga/SAM_Weather_Data
    # Fallback to creating a dummy or copying from SAM install if not properly linked
    find /opt/SAM -name "*phoenix*" -o -name "*Phoenix*" | head -1 | xargs -I {} cp {} /home/ga/SAM_Weather_Data/phoenix_az_tmy.csv 2>/dev/null || true
    chown -R ga:ga /home/ga/SAM_Weather_Data
fi

# Take initial screenshot showing terminal ready
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="