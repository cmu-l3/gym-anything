#!/bin/bash
echo "=== Setting up soiling impact analysis task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists and is clean
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects
rm -f /home/ga/Documents/SAM_Projects/soiling_analysis.json

# Locate SAM directory and solar resource
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

SOLAR_RES=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
fi
if [ -z "$SOLAR_RES" ]; then
    SOLAR_RES=$(find /opt/SAM -type d -name "solar_resource" 2>/dev/null | head -1)
fi

if [ -n "$SOLAR_RES" ]; then
    echo "$SOLAR_RES" > /home/ga/.SAM/solar_resource_dir.txt
    chown ga:ga /home/ga/.SAM/solar_resource_dir.txt
    
    # Recommend an Arizona or desert weather file
    AZ_FILE=$(find "$SOLAR_RES" -iname "*phoenix*" -o -iname "*tucson*" -o -iname "*arizona*" -o -iname "*daggett*" 2>/dev/null | head -1)
    if [ -n "$AZ_FILE" ]; then
        echo "$AZ_FILE" > /home/ga/.SAM/recommended_weather_file.txt
    else
        ANY_FILE=$(find "$SOLAR_RES" -name "*.csv" 2>/dev/null | head -1)
        if [ -n "$ANY_FILE" ]; then
            echo "$ANY_FILE" > /home/ga/.SAM/recommended_weather_file.txt
        fi
    fi
    chown ga:ga /home/ga/.SAM/recommended_weather_file.txt 2>/dev/null || true
fi

# Verify PySAM is available
python3 -c "import PySAM.Pvwattsv8" 2>/dev/null || echo "WARNING: PySAM.Pvwattsv8 not available"

# Start SAM GUI to establish proper initial state (even though task is programmatic)
if [ -n "$SAM_DIR" ] && ! pgrep -f "sam" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 LD_LIBRARY_PATH='${SAM_DIR}/linux_64:${SAM_DIR}:\$LD_LIBRARY_PATH' /usr/local/bin/sam > /dev/null 2>&1 &"
    sleep 5
    # Dismiss any registration dialogs
    DISPLAY=:1 xdotool key Escape 2>/dev/null || true
    sleep 1
fi

# Ensure a terminal is open and focused for the agent
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi
DISPLAY=:1 wmctrl -a "Terminal" 2>/dev/null || true

# Take initial screenshot showing setup is complete
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || \
    DISPLAY=:1 import -window root /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="