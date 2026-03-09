#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Sleep Pattern Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy sleep log CSV with realistic inconsistencies
cat > /home/ga/Documents/sleep_log.csv << 'CSVEOF'
Date,Bedtime,Wake Time,Quality Score,Caffeine After 2PM,Screen Time (hours),Exercise,Notes
2024-01-01,11:30 PM,7:00 AM,6,Yes,3.5,No,Felt groggy
2024-01-02,10:45 PM,6:30 AM,8,No,1.5,Yes,Woke refreshed
2024-01-03,23:45,07:15,5,Yes,4.0,No,Couldn't fall asleep
2024-01-04,10:15 p.m.,6:45 a.m.,7,No,2.0,Yes,Pretty good
2024-01-05,01:00,09:00,4,Yes,5.5,No,Late night doom scrolling
2024-01-06,22:30,06:30,8,No,1.0,Yes,Excellent sleep
2024-01-07,11:00 PM,8:00 AM,7,no,2.5,No,Weekend sleep-in
2024-01-08,10:30 PM,6:45 AM,8,No,1.5,yes,Felt great
2024-01-09,23:00,07:00,7,No,2.0,Yes,Good energy
2024-01-10,11:45 p.m.,7:30 a.m.,6,YES,3.0,No,Tired at work
2024-01-11,22:45,06:45,8,No,1.0,Yes,Very refreshed
2024-01-12,10:00 PM,6:30 AM,9,No,1.0,Yes,Best sleep in weeks
2024-01-13,23:30,07:00,7,No,2.5,Yes,Decent
2024-01-14,00:30,08:30,5,Yes,4.5,No,Restless night
2024-01-15,22:00,06:00,8,No,1.5,Yes,Perfect timing
2024-01-16,10:45 PM,7:15 AM,8,No,1.5,Yes,Consistent pattern
2024-01-17,23:15,07:30,7,yes,2.5,No,OK but not great
2024-01-18,11:00 p.m.,7:00 a.m.,6,Yes,3.5,No,Caffeine effect?
2024-01-19,22:30,06:45,9,No,0.5,Yes,Amazing sleep
2024-01-20,10:30 PM,6:30 AM,8,No,1.0,Yes,Feeling healthy
2024-01-21,00:00,08:00,6,Yes,4.0,No,Late bedtime
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sleep_log.csv
sudo chmod 666 /home/ga/Documents/sleep_log.csv

echo "✅ Created sleep_log.csv with messy data"

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/sleep_log.csv > /tmp/calc_sleep_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_sleep_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Sleep Pattern Optimizer Task Setup Complete ==="
echo ""
echo "📊 TASK: Analyze Sleep Patterns and Optimize Bedtime"
echo ""
echo "🎯 Your Goals:"
echo "  1. Calculate sleep duration (handle midnight crossover!)"
echo "  2. Categorize sleep quality (Excellent/Good/Fair/Poor)"
echo "  3. Apply conditional formatting to visualize patterns"
echo "  4. Use AVERAGEIF to correlate factors with quality"
echo "  5. Identify optimal bedtime window"
echo ""
echo "💡 Key Challenges:"
echo "  - Time formats are inconsistent (11:30 PM vs 23:30)"
echo "  - Calculate hours slept across midnight"
echo "  - Use statistical formulas to find patterns"
echo ""
echo "📝 Data loaded from: /home/ga/Documents/sleep_log.csv"
echo "💾 Save as: /home/ga/Documents/sleep_analysis.ods"