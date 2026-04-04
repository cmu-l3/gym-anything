#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Running Pace Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with messy running data
cat > /home/ga/Documents/training_log.csv << 'CSVEOF'
Date,Distance,DistanceUnit,Time,TimeFormat,ElevationGain,RunType
2024-01-05,5.0,miles,00:45:30,HH:MM:SS,120,Easy
2024-01-07,5.2,km,28.5,DecimalMinutes,45,Tempo
2024-01-10,10.0,miles,1.62,DecimalHours,250,Long
2024-01-12,3.1,miles,00:25:15,HH:MM:SS,80,Easy
2024-01-15,8.0,km,45.2,DecimalMinutes,,Tempo
2024-01-17,4.5,miles,00:38:45,HH:MM:SS,95,Easy
2024-01-20,6.2,km,35.8,DecimalMinutes,60,Tempo
2024-01-22,12.0,miles,1.98,DecimalHours,180,Long
2024-01-24,5.0,miles,00:43:20,HH:MM:SS,110,Easy
2024-01-27,10.0,km,58.3,DecimalMinutes,85,Tempo
2024-01-29,3.5,miles,00:28:30,HH:MM:SS,70,Easy
2024-02-01,13.1,miles,2.15,DecimalHours,220,Long
2024-02-03,5.0,miles,00:42:15,HH:MM:SS,100,Easy
2024-02-05,5.0,km,26.7,DecimalMinutes,50,Tempo
2024-02-08,6.0,miles,00:51:30,HH:MM:SS,140,Easy
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/training_log.csv
sudo chmod 666 /home/ga/Documents/training_log.csv

echo "✅ Created training_log.csv with messy running data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/training_log.csv > /tmp/calc_pace_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_pace_task.log || true
    # Don't exit - continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - continue anyway
fi

# Click on center of the screen to select current desktop (should be done in all tasks), and then focus window.
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Running Pace Analyzer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create 'Distance_Miles' column: =IF(C2=\"km\", B2*0.621371, B2)"
echo "  2. Create 'Time_Minutes' column with format handling"
echo "  3. Create 'Pace_MinPerMile' column: =Time_Minutes/Distance_Miles"
echo "  4. Apply conditional formatting to highlight fastest paces"
echo "  5. Calculate average pace by run type (Easy, Tempo, Long)"
echo "  6. Save the file"