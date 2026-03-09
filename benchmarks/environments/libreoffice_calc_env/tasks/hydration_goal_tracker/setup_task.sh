#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Daily Hydration Goal Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create ODS file with water intake data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText
import datetime

# Sample water intake data for 14 days (oz)
# Format: (date, morning, afternoon, evening)
water_data = [
    ("2024-01-01", 16, 24, 18),  # Total: 58 - No
    ("2024-01-02", 20, 20, 28),  # Total: 68 - Yes
    ("2024-01-03", 12, 16, 20),  # Total: 48 - No
    ("2024-01-04", 18, 28, 22),  # Total: 68 - Yes
    ("2024-01-05", 22, 20, 24),  # Total: 66 - Yes
    ("2024-01-06", 14, 18, 16),  # Total: 48 - No
    ("2024-01-07", 16, 20, 20),  # Total: 56 - No
    ("2024-01-08", 24, 22, 26),  # Total: 72 - Yes
    ("2024-01-09", 20, 24, 20),  # Total: 64 - Yes
    ("2024-01-10", 18, 18, 18),  # Total: 54 - No
    ("2024-01-11", 22, 24, 20),  # Total: 66 - Yes
    ("2024-01-12", 20, 26, 22),  # Total: 68 - Yes
    ("2024-01-13", 16, 22, 24),  # Total: 62 - No
    ("2024-01-14", 24, 24, 24),  # Total: 72 - Yes
]

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Hydration Log"
table = Table(name="Hydration Log")
doc.spreadsheet.addElement(table)

# Create header row
header_row = TableRow()
headers = ["Date", "Morning (oz)", "Afternoon (oz)", "Evening (oz)", "Daily Total (oz)", "Goal Met?"]
for header in headers:
    cell = TableCell(valuetype="string")
    p = P(text=header)
    cell.addElement(p)
    header_row.addElement(cell)
table.addElement(header_row)

# Add data rows
for date_str, morning, afternoon, evening in water_data:
    row = TableRow()
    
    # Date cell
    cell = TableCell(valuetype="string")
    p = P(text=date_str)
    cell.addElement(p)
    row.addElement(cell)
    
    # Morning oz
    cell = TableCell(valuetype="float", value=str(morning))
    p = P(text=str(morning))
    cell.addElement(p)
    row.addElement(cell)
    
    # Afternoon oz
    cell = TableCell(valuetype="float", value=str(afternoon))
    p = P(text=str(afternoon))
    cell.addElement(p)
    row.addElement(cell)
    
    # Evening oz
    cell = TableCell(valuetype="float", value=str(evening))
    p = P(text=str(evening))
    cell.addElement(p)
    row.addElement(cell)
    
    # Daily Total (empty - agent will add formula)
    cell = TableCell()
    row.addElement(cell)
    
    # Goal Met (empty - agent will add formula)
    cell = TableCell()
    row.addElement(cell)
    
    table.addElement(row)

# Add empty row
empty_row = TableRow()
for _ in range(6):
    cell = TableCell()
    empty_row.addElement(cell)
table.addElement(empty_row)

# Add rows for statistics labels and formulas (agent will fill)
# Row for average
stats_row1 = TableRow()
for i in range(6):
    cell = TableCell()
    if i == 3:  # Column D - label area
        cell = TableCell(valuetype="string")
        p = P(text="Average Daily Intake:")
        cell.addElement(p)
    stats_row1.addElement(cell)
table.addElement(stats_row1)

# Row for count
stats_row2 = TableRow()
for i in range(6):
    cell = TableCell()
    if i == 3:  # Column D - label area
        cell = TableCell(valuetype="string")
        p = P(text="Days Goal Met:")
        cell.addElement(p)
    stats_row2.addElement(cell)
table.addElement(stats_row2)

# Add more empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/hydration_data.ods"
doc.save(output_path)
print(f"Created hydration tracking spreadsheet: {output_path}")
print(f"Data rows: {len(water_data)}")
print("Expected average: ~61.7 oz/day")
print("Expected days meeting goal (64+ oz): 8 out of 14")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/hydration_data.ods
sudo chmod 666 /home/ga/Documents/hydration_data.ods

echo "✅ Created hydration_data.ods with 14 days of water intake data"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/hydration_data.ods > /tmp/calc_hydration_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_hydration_task.log || true
    # Don't exit, continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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

# Position cursor at E2 (Daily Total column, first data row)
echo "Positioning cursor at E2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Daily Hydration Goal Tracker Task Setup Complete ==="
echo "📊 Task Overview:"
echo "  • 14 days of water intake data provided"
echo "  • Goal: 64 oz/day"
echo ""
echo "📝 Required Actions:"
echo "  1. Add Daily Total formulas in column E (=SUM(B2:D2) for each row)"
echo "  2. Add Goal Met formulas in column F (=IF(E2>=64,\"Yes\",\"No\") for each row)"
echo "  3. Calculate average daily intake (=AVERAGE(E2:E15))"
echo "  4. Count days goal was met (=COUNTIF(F2:F15,\"Yes\"))"
echo ""
echo "💡 Tip: Cursor is positioned at E2 to start adding the first daily total formula"