#!/bin/bash
echo "=== Setting up evaluate_climate_warming_pv_impact task ==="

# Record task start time for anti-gaming checks
date +%s > /home/ga/.task_start_time

# Ensure required directories exist
mkdir -p /home/ga/Documents/SAM_Projects
mkdir -p /home/ga/SAM_Weather_Data
chown -R ga:ga /home/ga/Documents /home/ga/SAM_Weather_Data

# Clean up any previous run artifacts
rm -f /home/ga/Documents/SAM_Projects/climate_risk_report.json 2>/dev/null || true
rm -f /home/ga/SAM_Weather_Data/phoenix_plus_3c.csv 2>/dev/null || true
rm -f /tmp/task_result.json 2>/dev/null || true
rm -f /home/ga/*.py /home/ga/Documents/SAM_Projects/*.py 2>/dev/null || true

# Locate and copy a baseline weather file to ensure it's available exactly where specified
BASE_WEATHER="/home/ga/SAM_Weather_Data/phoenix_az_tmy.csv"
if [ ! -f "$BASE_WEATHER" ]; then
    echo "Locating SAM bundled weather data..."
    # Try finding Phoenix data
    PHOENIX_FILE=$(find /opt/SAM -name "*phoenix*.csv" -o -name "*Phoenix*.csv" 2>/dev/null | head -n 1)
    
    if [ -n "$PHOENIX_FILE" ]; then
        cp "$PHOENIX_FILE" "$BASE_WEATHER"
        echo "Copied $PHOENIX_FILE to $BASE_WEATHER"
    else
        # Fallback to any valid TMY file in solar_resource
        ANY_FILE=$(find /opt/SAM -type f -name "*.csv" | grep -i "solar_resource" | head -n 1)
        if [ -n "$ANY_FILE" ]; then
            cp "$ANY_FILE" "$BASE_WEATHER"
            echo "Copied fallback $ANY_FILE to $BASE_WEATHER"
        else
            echo "WARNING: Could not find bundled SAM weather data."
            # The agent will have to fail or download one, but SAM standard install guarantees one.
        fi
    fi
fi
chown ga:ga "$BASE_WEATHER" 2>/dev/null || true
chmod 644 "$BASE_WEATHER" 2>/dev/null || true

# Open a terminal for the agent if one isn't open
if ! DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "terminal"; then
    su - ga -c "DISPLAY=:1 gnome-terminal --geometry=120x40 2>/dev/null &"
    sleep 2
fi

echo "=== Task setup complete ==="