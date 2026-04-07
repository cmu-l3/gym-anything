#!/bin/bash
echo "=== Setting up quantify_pv_heatwave_loss task ==="

# Record task start time
date +%s > /home/ga/.task_start_time

# Clean any pre-existing output files from previous runs
rm -f /home/ga/Documents/SAM_Projects/heatwave_impact.json 2>/dev/null || true
rm -f /home/ga/SAM_Weather_Data/phoenix_heatwave.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/pv_*.py /home/ga/sam_*.py 2>/dev/null || true

# Ensure directories exist
mkdir -p /home/ga/Documents/SAM_Projects
mkdir -p /home/ga/SAM_Weather_Data
chown -R ga:ga /home/ga/Documents
chown -R ga:ga /home/ga/SAM_Weather_Data

# Ensure baseline weather file exists
BASELINE_FILE="/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
if [ ! -f "$BASELINE_FILE" ]; then
    echo "Baseline weather file not found at expected location, searching SAM installation..."
    # Find any TMY file in the SAM solar_resource directory to use as fallback
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt 2>/dev/null || echo "/opt/SAM/current")
    FALLBACK_FILE=$(find "$SAM_DIR" -type f -name "*.csv" | grep -i "tmy" | head -n 1)
    
    if [ -n "$FALLBACK_FILE" ]; then
        cp "$FALLBACK_FILE" "$BASELINE_FILE"
        echo "Copied fallback weather file from $FALLBACK_FILE"
    else
        echo "WARNING: Could not find any suitable TMY weather file!"
    fi
fi
chmod 644 "$BASELINE_FILE"
chown ga:ga "$BASELINE_FILE"

# Ensure a terminal is available for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="