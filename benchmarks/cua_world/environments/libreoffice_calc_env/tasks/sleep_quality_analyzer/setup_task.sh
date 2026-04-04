#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Sleep Quality Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create sleep tracking CSV data
cat > /home/ga/Documents/sleep_data.csv << 'CSVEOF'
Date,Bedtime,Wake Time,Time in Bed (hrs),Time Asleep (hrs),Caffeine After 2pm,Screen Time Before Bed (mins)
2024-01-15,23:30,07:00,7.5,6.8,N,15
2024-01-16,23:45,06:45,7.0,6.2,Y,45
2024-01-17,00:15,07:15,7.0,6.5,Y,60
2024-01-18,22:30,06:30,8.0,7.2,N,20
2024-01-19,23:00,06:00,7.0,5.8,Y,90
2024-01-20,23:15,07:45,8.5,7.8,N,10
2024-01-21,00:30,07:00,6.5,5.5,Y,75
2024-01-22,23:00,07:30,8.5,7.5,N,15
2024-01-23,23:45,06:30,6.75,6.0,Y,50
2024-01-24,22:45,07:00,8.25,7.6,N,25
2024-01-25,23:30,06:15,6.75,5.9,N,80
2024-01-26,23:00,07:15,8.25,7.4,N,30
2024-01-27,00:00,07:30,7.5,6.9,N,40
2024-01-28,23:15,06:45,7.5,6.7,Y,55
CSVEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sleep_data.csv
sudo chmod 644 /home/ga/Documents/sleep_data.csv

echo "✅ Created sleep_data.csv with 14 nights of tracking data"

# Create a blank ODS workbook for the task
echo "Creating blank workbook..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Add empty rows to make it a proper spreadsheet
for _ in range(50):
    row = TableRow()
    for _ in range(15):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/sleep_analysis_complete.ods")
print("Created blank workbook for analysis")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/sleep_analysis_complete.ods
sudo chmod 666 /home/ga/Documents/sleep_analysis_complete.ods

# Launch LibreOffice Calc with blank workbook
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/sleep_analysis_complete.ods > /tmp/calc_sleep_task.log 2>&1 &"

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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Sleep Quality Analyzer Task Setup Complete ==="
echo ""
echo "📊 Task Instructions:"
echo "  1. Open the sleep_data.csv file (File → Open → /home/ga/Documents/sleep_data.csv)"
echo "  2. Calculate Sleep Efficiency (%) in column H: =(E3/D3)*100"
echo "  3. Copy the formula down for all 14 data rows"
echo "  4. Calculate Average Sleep: =AVERAGE(E3:E16) in summary area"
echo "  5. Count poor sleep nights: =COUNTIF(E3:E16,\"<7\") in summary area"
echo "  6. Apply conditional formatting to column E (Time Asleep):"
echo "     - Select E3:E16"
echo "     - Format → Conditional Formatting → Condition"
echo "     - Cell value is less than 7"
echo "     - Apply red background or text"
echo "  7. Save the file (Ctrl+S)"
echo ""
echo "💡 Expected Results:"
echo "  - Sleep Efficiency column with percentages (e.g., 90.67% for first night)"
echo "  - Average Sleep ≈ 6.8 hours"
echo "  - 5 nights with <7 hours sleep (highlighted in red)"