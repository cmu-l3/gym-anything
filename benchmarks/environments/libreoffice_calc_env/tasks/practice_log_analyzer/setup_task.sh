#!/bin/bash
# set -euo pipefail

echo "=== Setting up Practice Log Analyzer Task ==="

source /workspace/scripts/task_utils.sh

# Create directory if needed
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with realistic practice log data
cat > /home/ga/Documents/practice_log.csv << 'EOF'
Student Name,Weekly Goal (min),Week 1,Week 2,Week 3,Week 4
Emma Johnson,120,130,125,115,140
Marcus Lee,90,95,85,,80
Sophia Chen,150,60,55,70,65
Liam Brown,60,65,70,68,72
Olivia Martinez,120,140,145,135,150
Noah Davis,90,45,40,35,30
Ava Wilson,150,155,160,150,165
Ethan Anderson,60,30,25,28,20
Isabella Thomas,120,100,105,110,115
Mason Taylor,90,92,88,90,95
Charlotte Moore,150,80,85,75,70
James Jackson,60,0,15,20,25
Mia White,120,125,120,,118
Lucas Harris,90,90,95,92,88
Amelia Martin,150,145,140,155,160
EOF

chown ga:ga /home/ga/Documents/practice_log.csv
chmod 644 /home/ga/Documents/practice_log.csv

echo "✅ Created practice_log.csv with 15 students"
ls -lh /home/ga/Documents/practice_log.csv

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/practice_log.csv > /tmp/calc_practice_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_practice_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Position cursor at first data row, column F (where Total Practice should go)
echo "Positioning cursor..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right  # Move to column F
sleep 0.3

echo "=== Practice Log Analyzer Task Setup Complete ==="
echo "📋 Task: Analyze student practice logs"
echo "📝 Instructions:"
echo "  1. Calculate Total Practice (F2): =SUM(C2:F2)"
echo "  2. Calculate Total Goal (G2): =B2*4"
echo "  3. Calculate % of Goal (H2): =(F2/G2)*100"
echo "  4. Create Status (I2): =IF(H2>=100,\"Excellent\",IF(H2>=80,\"On Track\",IF(H2>=50,\"Needs Encouragement\",\"Urgent Check-in\")))"
echo "  5. Calculate Weeks Reported (J2): =COUNTA(C2:F2)"
echo "  6. Calculate Weeks Goal Met (K2): =COUNTIF(C2:F2,\">=\"&B2)"
echo "  7. Copy formulas down to all students"
echo "  8. Apply conditional formatting to column H (% of Goal)"
echo "💡 Hint: Some students have missing data - formulas should handle this"