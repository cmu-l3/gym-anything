#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tide Window Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create realistic tide data for Cape Cod area (7 days, semi-diurnal tides)
# Includes mix of optimal and non-optimal conditions
cat > /home/ga/Documents/cape_cod_tides.csv << 'TIDEEOF'
Date,Time,Height_ft,Type
2024-03-18,05:23,0.8,Low
2024-03-18,11:45,9.2,High
2024-03-18,17:34,1.2,Low
2024-03-18,23:58,8.9,High
2024-03-19,06:15,0.6,Low
2024-03-19,12:38,9.4,High
2024-03-19,18:27,1.4,Low
2024-03-20,00:52,8.7,High
2024-03-20,07:09,0.9,Low
2024-03-20,13:32,9.1,High
2024-03-20,19:21,1.6,Low
2024-03-21,01:47,8.5,High
2024-03-21,08:05,1.1,Low
2024-03-21,14:28,8.8,High
2024-03-21,20:17,1.8,Low
2024-03-22,02:43,8.3,High
2024-03-22,09:03,1.3,Low
2024-03-22,15:26,8.6,High
2024-03-22,21:15,2.0,Low
2024-03-23,03:41,8.1,High
2024-03-23,10:04,1.5,Low
2024-03-23,16:27,8.4,High
2024-03-23,22:16,2.1,Low
2024-03-24,04:42,7.9,High
2024-03-24,11:08,1.4,Low
2024-03-24,17:31,8.2,High
2024-03-24,23:19,2.2,Low
2024-03-25,05:45,7.8,High
TIDEEOF

# Set proper permissions
sudo chown ga:ga /home/ga/Documents/cape_cod_tides.csv
sudo chmod 644 /home/ga/Documents/cape_cod_tides.csv

echo "✅ Created tide data CSV file"
ls -lh /home/ga/Documents/cape_cod_tides.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with tide data..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/cape_cod_tides.csv > /tmp/calc_tide_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tide_task.log || true
    # exit 1  # Don't exit to allow retry
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1  # Don't exit to allow retry
fi

# Click on center of screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus Calc window
echo "Focusing Calc window..."
wid=$(get_calc_window_id)
if [ -n "$wid" ]; then
    if focus_window "$wid"; then
        # Maximize window
        safe_xdotool ga :1 key F11
        sleep 0.5
    fi
fi

# Move to cell E1 to prepare for formula entry
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Tide Window Calculator Task Setup Complete ==="
echo ""
echo "📊 Tide Data Loaded: Cape Cod, MA (March 18-25, 2024)"
echo "🌊 28 tide events (14 lows, 14 highs) over 7 days"
echo ""
echo "📝 Your Task:"
echo "   1. Identify LOW tides (filter out high tides)"
echo "   2. Find low tides during DAYLIGHT (7:00 AM - 7:00 PM)"
echo "   3. Filter for OPTIMAL HEIGHT (≤ 1.5 feet)"
echo "   4. Calculate ACTIVITY WINDOW duration (time until tide returns)"
echo "   5. Mark days that meet ALL criteria"
echo "   6. Create SUMMARY statistics:"
echo "      - Total low tides"
echo "      - Low tides in daylight"
echo "      - Optimal tides (meeting all criteria)"
echo "      - List of recommended days"
echo ""
echo "💡 Hints:"
echo "   - Use HOUR() function to extract hour from time"
echo "   - Use AND() to combine multiple conditions"
echo "   - Time window: AND(HOUR(B2)>=7, HOUR(B2)<19)"
echo "   - Use COUNTIF/COUNTIFS for summary statistics"
echo ""
echo "🎯 Goal: Help coastal enthusiasts find the best times for tidepooling!"