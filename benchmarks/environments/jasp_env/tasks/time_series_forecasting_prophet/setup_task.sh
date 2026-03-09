#!/bin/bash
set -e
echo "=== Setting up Time Series Forecasting (Prophet) task ==="

# 1. Record task start time (critical for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# 2. Prepare Data Directory
mkdir -p /home/ga/Documents/JASP

# 3. Download Real Data: Airline Passengers
# This is a standard public domain dataset for time series
CSV_PATH="/home/ga/Documents/JASP/AirlinePassengers.csv"

echo "Downloading AirlinePassengers.csv..."
curl -L -o "$CSV_PATH" \
    "https://raw.githubusercontent.com/jbrownlee/Datasets/master/airline-passengers.csv"

# Verify download and fix permissions
if [ -s "$CSV_PATH" ]; then
    echo "Data downloaded successfully ($(stat -c%s "$CSV_PATH") bytes)."
    chown ga:ga "$CSV_PATH"
    chmod 644 "$CSV_PATH"
else
    echo "ERROR: Failed to download dataset."
    # Create a fallback/dummy if network fails (though env should have net)
    echo "Month,Passengers" > "$CSV_PATH"
    echo "1949-01,112" >> "$CSV_PATH"
    echo "1949-02,118" >> "$CSV_PATH"
    echo "1949-03,132" >> "$CSV_PATH"
    chown ga:ga "$CSV_PATH"
fi

# 4. Clean up previous artifacts
rm -f /home/ga/Documents/JASP/PassengerForecast.jasp 2>/dev/null || true

# 5. Start JASP (if not running)
# Note: JASP in this env requires custom launch flags handled by launch-jasp
if ! pgrep -f "org.jaspstats.JASP" > /dev/null; then
    echo "Starting JASP..."
    su - ga -c "setsid /usr/local/bin/launch-jasp > /dev/null 2>&1 &"
    
    # Wait for window
    for i in {1..40}; do
        if DISPLAY=:1 wmctrl -l | grep -i "JASP"; then
            echo "JASP window detected."
            break
        fi
        sleep 1
    done
    sleep 5
fi

# 6. Maximize JASP window
DISPLAY=:1 wmctrl -r "JASP" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "JASP" 2>/dev/null || true

# 7. Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="