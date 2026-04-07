#!/bin/bash
echo "=== Setting up Solar Water Heating task ==="

# Record task start time (anti-gaming)
date +%s > /tmp/task_start_time.txt

# Ensure output directory exists
mkdir -p /home/ga/Documents/SAM_Projects
chown -R ga:ga /home/ga/Documents/SAM_Projects

# Remove any pre-existing result file (clean state)
rm -f /home/ga/Documents/SAM_Projects/swh_results.json
rm -f /home/ga/*.py /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Ensure weather data directory is available
WEATHER_DIR="/home/ga/SAM_Weather_Data"
mkdir -p "$WEATHER_DIR"

# Find SAM's solar_resource directory
SAM_DIR=""
if [ -f "/opt/SAM/sam_dir.txt" ]; then
    SAM_DIR=$(cat /opt/SAM/sam_dir.txt)
fi

SOLAR_RES=""
if [ -n "$SAM_DIR" ]; then
    SOLAR_RES=$(find "$SAM_DIR" -type d -name "solar_resource" 2>/dev/null | head -1)
fi

# Find a suitable weather file (prefer Phoenix/AZ for southwestern US)
WEATHER_FILE=""
if [ -n "$SOLAR_RES" ]; then
    # Try Phoenix first
    WEATHER_FILE=$(find "$SOLAR_RES" -iname "*phoenix*" -type f 2>/dev/null | head -1)
    # Try Tucson
    if [ -z "$WEATHER_FILE" ]; then
        WEATHER_FILE=$(find "$SOLAR_RES" -iname "*tucson*" -type f 2>/dev/null | head -1)
    fi
    # Try Daggett
    if [ -z "$WEATHER_FILE" ]; then
        WEATHER_FILE=$(find "$SOLAR_RES" -iname "*daggett*" -type f 2>/dev/null | head -1)
    fi
    # Try any .csv weather file as last resort
    if [ -z "$WEATHER_FILE" ]; then
        WEATHER_FILE=$(find "$SOLAR_RES" -name "*.csv" -type f 2>/dev/null | head -1)
    fi
fi

# Copy to known location
if [ -n "$WEATHER_FILE" ] && [ -f "$WEATHER_FILE" ]; then
    cp "$WEATHER_FILE" "$WEATHER_DIR/tmy_weather.csv"
    echo "Weather file prepared: $WEATHER_FILE -> $WEATHER_DIR/tmy_weather.csv"
else
    echo "WARNING: No weather file found in SAM installation"
    # Create a dummy if missing to prevent complete crash (though agent should fail in this case)
    echo "Date,Time,GHI,DNI,DHI,Tdry,Tdew,RH,Pres,Wspd,Wdir,Albedo" > "$WEATHER_DIR/tmy_weather.csv"
fi

chown -R ga:ga "$WEATHER_DIR"

# Verify PySAM Swh module is available and cache it implicitly
python3 -c "
import PySAM.Swh as Swh
swh = Swh.default('SolarWaterHeatingResidential')
print('PySAM.Swh default config loaded successfully')
" > /tmp/pysam_swh_check.log 2>&1 || true

# Ensure terminal is available for the agent
if ! pgrep -f "gnome-terminal" > /dev/null 2>&1; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 3
fi

# Maximize the terminal for better visibility
DISPLAY=:1 wmctrl -r "Terminal" -b add,maximized_vert,maximized_horz 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 import -window root /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Solar Water Heating task setup complete ==="