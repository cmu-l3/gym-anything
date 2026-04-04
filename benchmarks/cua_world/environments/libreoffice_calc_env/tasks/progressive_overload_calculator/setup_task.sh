#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Progressive Overload Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create workout log CSV with 8 weeks of messy data
cat > /home/ga/Documents/workout_log.csv << 'CSVEOF'
Date,Exercise,Weight,Reps Completed,Target Reps,Notes
2024-01-01,Squat,225,5,5,
2024-01-01,Bench Press,185,5,5,
2024-01-03,Barbell Row,155,5,5,
2024-01-03,Overhead Press,115,4,5,Struggled today
2024-01-05,Squat,225,5,5,
2024-01-05,Deadlift,315,5,5,
2024-01-08,Squat,225,5,5,Feeling strong
2024-01-08,Bench Press,185,5,5,
2024-01-10,Barbell Row,155,5,5,
2024-01-10,Overhead Press,115,5,5,Better today
2024-01-12,Squat,235,3,5,Increased too soon - failed
2024-01-12,Deadlift,315,5,5,
2024-01-15,Squat,225,5,5,Back to previous weight
2024-01-15,Bench Press,185,5,5,
2024-01-17,Barbell Row,155,5,5,
2024-01-17,Overhead Press,115,5,5,
2024-01-19,Squat,225,5,5,
2024-01-19,Deadlift,315,4,5,Tired
2024-01-22,Bench Press,185,5,5,
2024-01-22,Barbell Row,155,4,5,
2024-01-24,Squat,225,5,5,
2024-01-24,Overhead Press,120,5,5,Increased weight
2024-01-26,Deadlift,315,5,5,
2024-01-26,Bench Press,190,5,5,Increased weight
2024-01-29,Squat,235,5,5,Proper progression
2024-01-29,Barbell Row,160,5,5,Increased weight
2024-01-31,Overhead Press,120,5,5,
2024-01-31,Deadlift,315,5,5,
2024-02-02,Squat,235,5,5,
2024-02-02,Bench Press,190,5,5,
2024-02-05,Barbell Row,160,5,5,
2024-02-05,Overhead Press,120,4,5,
2024-02-07,Squat,235,5,5,Ready for next jump
2024-02-07,Deadlift,325,5,5,Increased weight
2024-02-09,Bench Press,190,5,5,
2024-02-12,Squat,185,5,5,DELOAD WEEK
2024-02-12,Barbell Row,125,5,5,DELOAD WEEK
2024-02-14,Overhead Press,95,5,5,DELOAD WEEK
2024-02-14,Deadlift,250,5,5,DELOAD WEEK
2024-02-16,Bench Press,155,5,5,DELOAD WEEK
2024-02-19,Squat,235,5,5,Back to working weight
2024-02-19,Barbell Row,160,5,5,
2024-02-21,Overhead Press,120,5,5,
2024-02-21,Deadlift,325,5,5,
2024-02-23,Squat,235,5,5,
2024-02-23,Bench Press,190,5,5,
2024-02-26,Barbell Row,160,5,5,
2024-02-26,Overhead Press,120,5,5,
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/workout_log.csv
sudo chmod 666 /home/ga/Documents/workout_log.csv

echo "✅ Created workout log with 8 weeks of data (48 entries)"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/workout_log.csv > /tmp/calc_workout_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_workout_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop
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

# Position cursor at cell F1 (first helper column)
echo "Positioning cursor for helper columns..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column F (after Notes column E)
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.3

echo "=== Progressive Overload Calculator Task Setup Complete ==="
echo ""
echo "📋 Task Instructions:"
echo "  1. Create helper column F: 'Sessions at Current Weight' (use COUNTIFS)"
echo "  2. Create helper column G: 'Days Since Last Session' (use TODAY() and dates)"
echo "  3. Create helper column H: 'Ready for Increase?' (use IF/AND/NOT logic)"
echo "  4. Create helper column I: 'Recommended Weight' (add 5 or 10 lbs based on exercise)"
echo "  5. Apply conditional formatting to 'Ready for Increase?' column (green=YES, gray=NO)"
echo ""
echo "💡 Key Rules:"
echo "  - Need 3+ successful sessions at current weight"
echo "  - Must be < 14 days since last session"
echo "  - Exclude DELOAD weeks from progression"
echo "  - Upper body (Bench/OHP/Row): +5 lbs"
echo "  - Lower body (Squat/Deadlift): +10 lbs"