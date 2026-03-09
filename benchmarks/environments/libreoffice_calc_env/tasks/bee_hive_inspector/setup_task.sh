#!/bin/bash
# set -euo pipefail

echo "=== Setting up Bee Hive Inspector Task ==="

source /workspace/scripts/task_utils.sh

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create CSV with beekeeping inspection data (4 weeks, 5 hives, messy data)
cat > /home/ga/Documents/hive_inspections.csv << 'CSVEOF'
Week,Hive ID,Inspection Date,Population Estimate,Frames of Brood,Honey Stores,Disease Signs,Queen Seen
1,Hive-A,2024-04-01,Strong,9,Full,None,Yes
1,Hive-B,2024-04-01,Moderate,7,Adequate,None,Yes
1,Hive-C,2024-04-01,35000,6,Adequate,None seen,No
1,Hive-D,2024-04-01,Strong,8,Full,None,Yes
1,Hive-E,2024-04-01,Weak,4,Low,None,Yes
2,Hive-A,2024-04-08,52000,9,9,None seen,Yes
2,Hive-B,2024-04-08,42000,7,7,None,Yes
2,Hive-C,2024-04-08,28000,5,5,Possible,No
2,Hive-D,2024-04-08,Strong,8,8,None seen,Yes
2,Hive-E,2024-04-08,32000,5,4,None,Yes
3,Hive-A,2024-04-15,Strong,10,Full,None,Yes
3,Hive-B,2024-04-15,Moderate,8,Adequate,None,Yes
3,Hive-C,2024-04-15,Weak,4,Low,Possible varroa,No
3,Hive-D,2024-04-15,48000,9,9,None,Yes
3,Hive-E,2024-04-15,38000,6,6,None seen,Yes
4,Hive-A,2024-04-22,Strong,10,Full,None,Yes
4,Hive-B,2024-04-22,40000,8,7,None,Yes
4,Hive-C,2024-04-22,Weak,3,Low,Confirmed,No
4,Hive-D,2024-04-22,Strong,9,Full,None seen,Yes
4,Hive-E,2024-04-22,Moderate,6,Adequate,Possible,Yes
CSVEOF

chown ga:ga /home/ga/Documents/hive_inspections.csv
echo "✅ Created hive_inspections.csv with 4 weeks of data"

# Launch LibreOffice Calc with the CSV
echo "Launching LibreOffice Calc with inspection data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/hive_inspections.csv > /tmp/calc_hive_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_hive_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Ensure cursor is at top of sheet
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Bee Hive Inspector Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "════════════════════════════════════════════════════════════════"
echo "You are helping a beekeeper analyze colony health across 5 hives."
echo "The spreadsheet contains 4 weeks of inspection data (Week 1-4)."
echo ""
echo "YOUR GOAL: Calculate health scores for Week 4 hives and identify at-risk colonies."
echo ""
echo "HEALTH SCORING CRITERIA (Total: 0-23 points):"
echo "  Population Score:"
echo "    • Strong or >50,000 = 5 points"
echo "    • Moderate or 30,000-50,000 = 3 points"
echo "    • Weak or <30,000 = 1 point"
echo ""
echo "  Frames of Brood Score:"
echo "    • 8+ frames = 5 points"
echo "    • 5-7 frames = 3 points"
echo "    • <5 frames = 1 point"
echo ""
echo "  Honey Stores Score:"
echo "    • Full or >8 frames = 5 points"
echo "    • Adequate or 4-8 frames = 3 points"
echo "    • Low or <4 frames = 1 point"
echo ""
echo "  Disease Signs Score:"
echo "    • None = 5 points"
echo "    • Possible = 2 points"
echo "    • Confirmed = 0 points"
echo ""
echo "  Queen Present Bonus:"
echo "    • Yes = 3 points"
echo "    • No = 0 points"
echo ""
echo "REQUIRED ACTIONS:"
echo "  1. Add a 'Health Score' column (column I) for Week 4 data (rows 17-21)"
echo "  2. Create formulas to calculate health scores for all 5 Week 4 hives"
echo "  3. Apply conditional formatting to the Health Score column:"
echo "     • Red/Orange: Score <12 (URGENT - needs immediate attention)"
echo "     • Yellow: Score 12-17 (MONITOR - watch closely)"
echo "     • Green: Score 18+ (HEALTHY - continue regular inspections)"
echo ""
echo "TIP: The data contains mixed formats (text like 'Strong' and numbers like 40000)."
echo "     Use nested IF statements to handle both types of values."
echo "════════════════════════════════════════════════════════════════"