#!/bin/bash
echo "=== Setting up model_bifacial_pv_gain task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/bifacial_comparison.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents/SAM_Projects
mkdir -p /home/ga/.SAM
chown -R ga:ga /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/.SAM

# Locate a real TMY weather file from the SAM installation
WEATHER_FILE=$(find /opt/SAM -name "*.csv" | grep -i "solar_resource" | head -1)

# Fallback to the copied weather file if SAM install structure differs
if [ -z "$WEATHER_FILE" ] || [ ! -f "$WEATHER_FILE" ]; then
    if [ -f "/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv" ]; then
        WEATHER_FILE="/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
    else
        # Final fallback - create a dummy just so script doesn't completely break,
        # though SAM environment should have it downloaded.
        echo "WARNING: Could not find bundled weather file."
        WEATHER_FILE="/tmp/fallback_weather.csv"
        touch "$WEATHER_FILE"
    fi
fi

# Write path for agent to use
echo "$WEATHER_FILE" > /home/ga/.SAM/weather_file_path.txt
chown ga:ga /home/ga/.SAM/weather_file_path.txt
echo "Provided weather file: $WEATHER_FILE"

# Ensure PySAM is functioning quietly
python3 -c "import PySAM.Pvwattsv8" 2>/dev/null || echo "WARNING: PySAM.Pvwattsv8 import failed!"

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

# Take initial screenshot
DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="