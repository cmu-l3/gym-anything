#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Snow Removal Equity Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (for ODS file creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy for ODS file creation..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create the ODS file with two sheets using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== Sheet 1: Snow Events =====
snow_events = Table(name="Snow Events")

# Header row
header_row = TableRow()
for header in ["Date", "Day", "Who Shoveled"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
snow_events.addElement(header_row)

# Data rows (18 snow events)
events_data = [
    ("12/05/2024", "Thursday", "Johnson"),
    ("12/08/2024", "Sunday", "Smith"),
    ("12/12/2024", "Thursday", "Johnson"),
    ("12/18/2024", "Wednesday", "Patel"),
    ("12/22/2024", "Sunday", "Smith"),
    ("12/28/2024", "Saturday", "Johnson"),
    ("01/03/2025", "Friday", "Patel"),
    ("01/07/2025", "Tuesday", "Smith"),
    ("01/11/2025", "Saturday", "Johnson"),
    ("01/15/2025", "Wednesday", "Lee"),
    ("01/19/2025", "Sunday", "Patel"),
    ("01/23/2025", "Thursday", "Smith"),
    ("01/28/2025", "Tuesday", "Johnson"),
    ("02/02/2025", "Sunday", "Garcia"),
    ("02/06/2025", "Thursday", "Patel"),
    ("02/10/2025", "Monday", "Smith"),
    ("02/13/2025", "Thursday", "Lee"),
    ("02/16/2025", "Sunday", "Johnson"),
]

for date, day, who in events_data:
    row = TableRow()
    
    # Date cell
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=date))
    row.addElement(cell)
    
    # Day cell
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=day))
    row.addElement(cell)
    
    # Who Shoveled cell
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=who))
    row.addElement(cell)
    
    snow_events.addElement(row)

# Add some empty rows for padding
for _ in range(10):
    row = TableRow()
    for _ in range(3):
        row.addElement(TableCell())
    snow_events.addElement(row)

doc.spreadsheet.addElement(snow_events)

# ===== Sheet 2: Household Summary =====
summary = Table(name="Household Summary")

# Header row
header_row = TableRow()
for header in ["Household", "Times Shoveled", "Fair Share", "Deficit/Surplus", "Makeup Shifts Needed"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
summary.addElement(header_row)

# Household names (only column A filled, rest empty for agent to complete)
households = ["Johnson", "Smith", "Patel", "Lee", "Garcia", "O'Brien"]

for household in households:
    row = TableRow()
    
    # Household name
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=household))
    row.addElement(cell)
    
    # Empty cells for formulas (4 columns: B, C, D, E)
    for _ in range(4):
        row.addElement(TableCell())
    
    summary.addElement(row)

# Empty row for TOTAL (agent should add this)
row = TableRow()
cell = TableCell(valuetype="string")
cell.addElement(P(text="TOTAL"))
row.addElement(cell)
for _ in range(4):
    row.addElement(TableCell())
summary.addElement(row)

# Add padding rows
for _ in range(15):
    row = TableRow()
    for _ in range(5):
        row.addElement(TableCell())
    summary.addElement(row)

doc.spreadsheet.addElement(summary)

# Save the file
doc.save("/home/ga/Documents/snow_equity.ods")
print("✅ Created snow_equity.ods with Snow Events and Household Summary sheets")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/snow_equity.ods
sudo chmod 666 /home/ga/Documents/snow_equity.ods

# Verify file was created
if [ -f "/home/ga/Documents/snow_equity.ods" ]; then
    echo "✅ ODS file created successfully"
    ls -lh /home/ga/Documents/snow_equity.ods
else
    echo "❌ ERROR: Failed to create ODS file"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/snow_equity.ods > /tmp/calc_snow_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_snow_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Navigate to Household Summary sheet (Sheet 2)
echo "Navigating to Household Summary sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Position cursor at B2 (first cell to fill with formula)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Snow Removal Equity Tracker Task Setup Complete ==="
echo ""
echo "📋 Scenario:"
echo "   It's mid-February and some neighbors have been shoveling constantly"
echo "   while others haven't contributed at all. Calculate makeup shifts!"
echo ""
echo "📊 Data Structure:"
echo "   - Sheet 1 'Snow Events': 18 logged snow removals (pre-filled)"
echo "   - Sheet 2 'Household Summary': 6 households (calculations needed)"
echo ""
echo "✏️  Your Tasks:"
echo "   1. In column B: Create COUNTIF formulas to count contributions"
echo "      Formula hint: =COUNTIF('Snow Events'.C:C, A2)"
echo "   2. In column C: Calculate fair share (18 events ÷ 6 households = 3)"
echo "   3. In column D: Calculate deficit/surplus (actual - fair share)"
echo "   4. In column E: Calculate makeup shifts (only for negative deficits)"
echo "      Formula hint: =IF(D2<0, ABS(D2), 0)"
echo "   5. Add totals row to validate your work"
echo ""
echo "🎯 Expected Results:"
echo "   - Johnson: 6 contributions (surplus +3, no makeup)"
echo "   - Smith: 5 contributions (surplus +2, no makeup)"
echo "   - Patel: 4 contributions (surplus +1, no makeup)"
echo "   - Lee: 2 contributions (deficit -1, needs 1 makeup)"
echo "   - Garcia: 1 contribution (deficit -2, needs 2 makeup)"
echo "   - O'Brien: 0 contributions (deficit -3, needs 3 makeup)"
echo ""
echo "✅ Success Criteria: All formulas correct, conservation law satisfied"