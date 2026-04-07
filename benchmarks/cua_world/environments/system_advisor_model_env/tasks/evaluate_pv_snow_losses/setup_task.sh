#!/bin/bash
echo "=== Setting up evaluate_pv_snow_losses task ==="

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/snow_loss_analysis.json 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true

# Clear any cached Python/SAM scripts from previous task runs
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true
rm -f /home/ga/Documents/SAM_Projects/*.sam 2>/dev/null || true

# Record task start time
date +%s > /home/ga/.task_start_time

# Ensure SAM Projects and Weather Data directories exist
mkdir -p /home/ga/Documents/SAM_Projects
mkdir -p /home/ga/SAM_Weather_Data

# Download Anchorage, AK EPW file (Real weather data)
EPW_FILE="/home/ga/SAM_Weather_Data/Anchorage.epw"
EPW_URL="https://energyplus-weather.s3.amazonaws.com/north_and_central_america_wmo_region_4/USA/AK/USA_AK_Anchorage.Intl.AP.702730_TMY3/USA_AK_Anchorage.Intl.AP.702730_TMY3.epw"

if [ ! -f "$EPW_FILE" ]; then
    echo "Downloading Anchorage EPW weather data..."
    curl -L -s -o "$EPW_FILE" "$EPW_URL" || wget -qO "$EPW_FILE" "$EPW_URL"
fi

# Set ownership
chown -R ga:ga /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/SAM_Weather_Data

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="