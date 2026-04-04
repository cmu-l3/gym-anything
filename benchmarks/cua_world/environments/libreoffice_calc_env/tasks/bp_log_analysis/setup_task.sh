#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Blood Pressure Log Analysis Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create realistic BP log CSV with 38 readings over 3 weeks
cat > /home/ga/Documents/bp_readings_3weeks.csv << 'CSVEOF'
Date,Time,Systolic,Diastolic,Pulse,Notes
2024-01-15,07:30,128,82,68,Morning reading before breakfast
2024-01-15,20:15,135,88,72,After dinner
2024-01-16,07:45,132,84,70,Felt stressed about work
2024-01-16,,,,,Forgot evening reading
2024-01-17,07:20,118,76,65,Felt relaxed
2024-01-17,19:45,142,91,78,After stressful day
2024-01-18,08:00,125,80,67,
2024-01-18,20:30,138,89,74,After light exercise
2024-01-19,07:15,122,78,66,Good night sleep
2024-01-19,19:30,136,86,73,Normal evening
2024-01-20,08:30,130,83,69,Weekend morning
2024-01-20,21:00,140,90,76,After watching sports
2024-01-21,09:00,124,79,64,Relaxed Sunday morning
2024-01-21,20:00,133,85,71,
2024-01-22,07:40,129,81,68,Back to work week
2024-01-22,19:45,141,92,77,Long work day
2024-01-23,07:25,126,80,66,
2024-01-23,20:15,137,87,73,After dinner walk
2024-01-24,08:15,131,84,70,Mid-week
2024-01-24,,,,,Missed evening reading
2024-01-25,07:35,123,77,65,Feeling good
2024-01-25,19:50,139,89,75,After gym workout
2024-01-26,08:00,127,81,67,
2024-01-26,20:45,143,93,79,Stressful evening
2024-01-27,09:15,125,79,64,Weekend relaxation
2024-01-27,21:00,134,86,72,
2024-01-28,09:30,121,76,63,Lazy Sunday
2024-01-28,20:30,138,88,74,
2024-01-29,07:45,130,83,69,New week
2024-01-29,19:30,144,94,80,Very busy day
2024-01-30,07:30,128,82,68,
2024-01-30,20:00,141,91,77,After project deadline
2024-01-31,08:00,124,78,66,Calmer day
2024-01-31,19:45,136,87,73,
2024-02-01,07:50,129,81,67,
2024-02-01,20:30,140,90,76,
2024-02-02,08:20,126,80,65,Feeling better
2024-02-02,19:55,135,86,72,More relaxed this week
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/bp_readings_3weeks.csv
sudo chmod 644 /home/ga/Documents/bp_readings_3weeks.csv

echo "✅ Created BP log CSV with 38 readings"

# Create a template ODS with instructions for the summary area
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="BP Analysis")
doc.spreadsheet.addElement(table)

# Add empty rows (will be filled with CSV data)
for _ in range(50):
    row = TableRow()
    for _ in range(12):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save
doc.save("/home/ga/Documents/bp_analysis_template.ods")
print("✅ Created template ODS")
PYEOF

sudo chown ga:ga /home/ga/Documents/bp_analysis_template.ods
sudo chmod 666 /home/ga/Documents/bp_analysis_template.ods

# Launch LibreOffice Calc with the CSV file
echo "Launching LibreOffice Calc with BP data..."
su - ga -c "DISPLAY=:1 libreoffice --calc /home/ga/Documents/bp_readings_3weeks.csv > /tmp/calc_bp_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_bp_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice" 90; then
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

# Position cursor at cell A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Blood Pressure Log Analysis Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📊 DATA: Blood pressure readings over 3 weeks are now loaded"
echo "   Columns: Date | Time | Systolic | Diastolic | Pulse | Notes"
echo ""
echo "🎯 YOUR TASKS:"
echo ""
echo "1️⃣  CREATE SUMMARY STATISTICS (in column H, starting row 2):"
echo "   H2: Overall average systolic"
echo "   H3: Overall average diastolic"
echo "   H4: Overall average pulse"
echo "   H5: (label) 'Morning Averages'"
echo "   H6: Morning average systolic (readings before 12:00 PM)"
echo "   H7: Morning average diastolic"
echo "   H8: (label) 'Evening Averages'"
echo "   H9: Evening average systolic (readings after 6:00 PM)"
echo "   H10: Evening average diastolic"
echo ""
echo "2️⃣  ADD STATUS COLUMN (column G) to categorize each reading:"
echo "   - 'Normal' if systolic <120 AND diastolic <80"
echo "   - 'Elevated' if systolic 120-129 AND diastolic <80"
echo "   - 'Stage 1' if systolic 130-139 OR diastolic 80-89"
echo "   - 'Stage 2' if systolic >=140 OR diastolic >=90"
echo "   - 'Crisis' if systolic >180 OR diastolic >120"
echo "   - Leave blank for missing data rows"
echo ""
echo "3️⃣  COUNT READINGS BY STATUS (in column H):"
echo "   H12: Count of 'Normal' readings"
echo "   H13: Count of 'Elevated' readings"
echo "   H14: Count of 'Stage 1' readings"
echo "   H15: Count of 'Stage 2' readings"
echo "   H16: Count of 'Crisis' readings"
echo ""
echo "4️⃣  (OPTIONAL) Apply conditional formatting to columns C & D:"
echo "   - Yellow: Systolic 130-139 OR Diastolic 80-89"
echo "   - Orange: Systolic 140-179 OR Diastolic 90-119"
echo "   - Red: Systolic >=180 OR Diastolic >=120"
echo ""
echo "💡 TIPS:"
echo "   - Use AVERAGE() for overall averages"
echo "   - Use AVERAGEIF() or AVERAGEIFS() for time-based averages"
echo "   - Use nested IF() statements for status categorization"
echo "   - Use COUNTIF() to count status occurrences"
echo "   - Handle blank cells gracefully in your formulas"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"