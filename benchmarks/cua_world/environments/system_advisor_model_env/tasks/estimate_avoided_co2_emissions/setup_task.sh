#!/bin/bash
echo "=== Setting up CO2 Emissions Estimation Task ==="

# Record task start time for anti-gaming
date +%s > /tmp/task_start_time.txt

# Clean up any previous task output
rm -f /home/ga/Documents/SAM_Projects/co2_avoided_report.json 2>/dev/null
rm -f /tmp/task_result.json 2>/dev/null

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Create config directory
mkdir -p /home/ga/.SAM
chown -R ga:ga /home/ga/.SAM

# Find SAM directory
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

# Locate a usable weather file from SAM's solar_resource directory
WEATHER_FILE=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
    if [ -n "$SOLAR_RES" ]; then
        # Prefer a file from a sunny location
        for pattern in "phoenix" "tucson" "daggett" "las_vegas" "sacramento" "denver"; do
            CANDIDATE=$(find "$SOLAR_RES" -name "*${pattern}*" -name "*.csv" 2>/dev/null | head -1)
            if [ -n "$CANDIDATE" ]; then
                WEATHER_FILE="$CANDIDATE"
                break
            fi
        done
        # Fallback: use any .csv file in solar_resource
        if [ -z "$WEATHER_FILE" ]; then
            WEATHER_FILE=$(find "$SOLAR_RES" -name "*.csv" -type f 2>/dev/null | head -1)
        fi
    fi
fi

# Second fallback: check user weather directory
if [ -z "$WEATHER_FILE" ]; then
    WEATHER_FILE=$(find /home/ga/SAM_Weather_Data -name "*.csv" -type f 2>/dev/null | head -1)
fi

if [ -n "$WEATHER_FILE" ]; then
    echo "Weather file found: $WEATHER_FILE"
    echo "$WEATHER_FILE" > /home/ga/.SAM/weather_file_for_task.txt
    chown ga:ga /home/ga/.SAM/weather_file_for_task.txt
else
    echo "WARNING: No weather file found. Task may fail."
    echo "" > /home/ga/.SAM/weather_file_for_task.txt
fi

# Verify PySAM is available
python3 -c "import PySAM.Pvwattsv8; print('PySAM Pvwattsv8 available')" 2>/dev/null || {
    echo "WARNING: PySAM Pvwattsv8 not available, attempting install..."
    pip3 install NREL-PySAM --break-system-packages 2>/dev/null || pip3 install NREL-PySAM || true
}

# Ensure a terminal is open for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Focus the terminal
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take screenshot of initial state
echo "Capturing initial state..."
sleep 1
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="
echo "Weather file: $(cat /home/ga/.SAM/weather_file_for_task.txt 2>/dev/null)"
echo "Task start time: $(cat /tmp/task_start_time.txt)"