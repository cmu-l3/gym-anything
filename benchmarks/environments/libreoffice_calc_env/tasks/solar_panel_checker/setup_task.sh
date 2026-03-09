#!/bin/bash
# set -euo pipefail

echo "=== Setting up Solar Panel Production Analyzer Task ==="

source /workspace/scripts/task_utils.sh

# Create CSV with realistic messy solar production data
cat > /home/ga/Documents/solar_production_log.csv << 'CSVEOF'
Date,Daily Production (kWh),System Status
2024-01-01,6.2,Normal
2024-01-02,ERROR,ERROR
2024-01-03,7.1,Normal
2024-01-04,,Offline
2024-01-05,5.8,Normal
2024-01-06,3.2,Normal
2024-01-07,6.9,Normal
2024-01-08,0.0,ERROR
2024-01-09,7.3,Normal
2024-01-10,6.5,Normal
2024-01-11,ERROR,ERROR
2024-01-12,5.9,Normal
2024-01-13,7.8,Normal
2024-01-14,6.1,Normal
2024-01-15,4.8,Normal
2024-01-16,7.2,Normal
2024-01-17,6.8,Normal
2024-01-18,,Offline
2024-01-19,5.5,Normal
2024-01-20,7.5,Normal
2024-01-21,3.8,Normal
2024-01-22,6.9,Normal
2024-01-23,7.1,Normal
2024-01-24,2.9,Normal
2024-01-25,6.4,Normal
2024-01-26,7.6,Normal
2024-01-27,5.7,Normal
2024-01-28,6.3,Normal
2024-01-29,ERROR,ERROR
2024-01-30,7.0,Normal
CSVEOF

chown ga:ga /home/ga/Documents/solar_production_log.csv
chmod 644 /home/ga/Documents/solar_production_log.csv
echo "✅ Created solar_production_log.csv with 30 days of messy data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/solar_production_log.csv > /tmp/calc_solar_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    if [ -f /tmp/calc_solar_task.log ]; then
        cat /tmp/calc_solar_task.log
    fi
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of screen to select current desktop
echo "Selecting desktop..."
su - ga -c "DISPLAY=:1 xdotool mousemove 600 400 click 1" || true
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

# Move cursor to beginning
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Solar Panel Analyzer Task Setup Complete ==="
echo ""
echo "📊 TASK: Analyze Solar Panel Production Data"
echo ""
echo "📋 Your Goals:"
echo "  1. Calculate average daily production (exclude ERROR/blank entries)"
echo "  2. Flag days producing < 80% of average (potential panel issues)"
echo "  3. Calculate total monthly production (valid days only)"
echo "  4. Calculate savings at \$0.12 per kWh"
echo "  5. Count how many days need inspection"
echo ""
echo "⚠️  Data Quality Issues Present:"
echo "  - Some cells contain 'ERROR' text"
echo "  - Some cells are blank (system offline)"
echo "  - Some days show 0 kWh (sensor failure)"
echo ""
echo "💡 Hints:"
echo "  - Use AVERAGEIF to exclude invalid data"
echo "  - Use IF formula with 80% threshold for flagging"
echo "  - Use SUMIF to total only valid production"
echo "  - Remember absolute references (\$E\$2) for threshold calculations"