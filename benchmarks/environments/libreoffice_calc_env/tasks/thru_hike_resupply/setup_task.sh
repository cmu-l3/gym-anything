#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Thru-Hike Resupply Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (needed for ODS creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create the trail planning spreadsheet with Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet named "PCT Section J"
table = Table(name="PCT Section J")

# Header row
header_row = TableRow()
headers = [
    "Day",
    "Daily Miles", 
    "Terrain",
    "Cumulative Distance",
    "Resupply Town",
    "Days to Next Resupply",
    "Food Weight (lbs)",
    "Pace Realistic?",
    "Date"
]

for header_text in headers:
    cell = TableCell(valuetype="string")
    p = P(text=header_text)
    cell.addElement(p)
    header_row.addElement(cell)

table.addElement(header_row)

# Trail data: 21 days with varying terrain
trail_data = [
    # Day, Daily Miles, Terrain, Resupply (empty except at towns)
    (1, 14.5, "Moderate", ""),
    (2, 15.2, "Easy", ""),
    (3, 13.8, "Moderate", ""),
    (4, 11.5, "Hard", ""),
    (5, 12.0, "Moderate", "Kennedy Meadows"),  # First resupply
    (6, 16.5, "Easy", ""),
    (7, 17.8, "Easy", ""),
    (8, 14.2, "Moderate", ""),
    (9, 10.5, "Hard", ""),
    (10, 9.8, "Very Hard", ""),
    (11, 11.2, "Hard", "Grumpy Bear"),  # Second resupply
    (12, 15.5, "Moderate", ""),
    (13, 16.8, "Easy", ""),
    (14, 18.2, "Easy", ""),
    (15, 13.5, "Moderate", ""),
    (16, 12.8, "Moderate", "Trail Pass"),  # Third resupply
    (17, 14.0, "Moderate", ""),
    (18, 11.5, "Hard", ""),
    (19, 10.2, "Hard", ""),
    (20, 15.8, "Moderate", ""),
    (21, 13.5, "Moderate", "Rock Creek"),  # Final resupply
]

for day, miles, terrain, resupply in trail_data:
    row = TableRow()
    
    # Day number
    cell = TableCell(valuetype="float", value=str(day))
    p = P(text=str(day))
    cell.addElement(p)
    row.addElement(cell)
    
    # Daily Miles
    cell = TableCell(valuetype="float", value=str(miles))
    p = P(text=str(miles))
    cell.addElement(p)
    row.addElement(cell)
    
    # Terrain
    cell = TableCell(valuetype="string")
    p = P(text=terrain)
    cell.addElement(p)
    row.addElement(cell)
    
    # Cumulative Distance (empty - agent must fill)
    cell = TableCell()
    row.addElement(cell)
    
    # Resupply Town
    cell = TableCell(valuetype="string")
    if resupply:
        p = P(text=resupply)
        cell.addElement(p)
    row.addElement(cell)
    
    # Days to Next Resupply (empty - agent must calculate)
    cell = TableCell()
    row.addElement(cell)
    
    # Food Weight (empty - agent must calculate)
    cell = TableCell()
    row.addElement(cell)
    
    # Pace Realistic? (empty - agent must validate)
    cell = TableCell()
    row.addElement(cell)
    
    # Date (empty - agent must calculate)
    cell = TableCell()
    row.addElement(cell)
    
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/resupply_plan.ods"
doc.save(output_path)
print(f"Created trail planning spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/resupply_plan.ods
sudo chmod 666 /home/ga/Documents/resupply_plan.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/resupply_plan.ods > /tmp/calc_resupply.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_resupply.log || true
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

# Position cursor at first empty formula cell (D2 - Cumulative Distance)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Thru-Hike Resupply Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  - 21-day PCT section hike planning"
echo "  - 4 resupply towns at days 5, 11, 16, 21"
echo "  - Start date: June 15, 2024"
echo ""
echo "📋 Required Calculations:"
echo "  Column D: Cumulative distance (running total)"
echo "  Column F: Days to next resupply"
echo "  Column G: Food weight = days × 2 lbs"
echo "  Column H: Validate pace vs terrain"
echo "  Column I: Calculate dates"
echo ""
echo "💡 Terrain Limits:"
echo "  Easy: ≤20 mi/day | Moderate: ≤15 | Hard: ≤12 | Very Hard: ≤8"