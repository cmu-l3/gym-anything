#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Hiking Time Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (should already be installed, but verify)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf
fi

# Create ODS file with trail data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create table
table = Table(name="Trail Calculator")

# Header row with bold styling
headers = [
    "Segment", 
    "Distance (km)", 
    "Elev Gain (m)", 
    "Elev Loss (m)", 
    "Base Time (hr)", 
    "Ascent Time (hr)", 
    "Descent Bonus (hr)", 
    "Total Time (hr)"
]

header_row = TableRow()
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Trail segment data
trail_data = [
    ["Trailhead to Creek", 3.2, 150, 20],
    ["Creek to Ridge", 4.5, 480, 30],
    ["Ridge to Summit", 2.8, 590, 10],
    ["Summit to Saddle", 2.1, 50, 420],
    ["Saddle to Viewpoint", 1.9, 180, 90],
    ["Viewpoint to Junction", 2.4, 30, 380],
    ["Junction to Trailhead", 3.1, 20, 250],
]

# Add data rows
for segment_data in trail_data:
    row = TableRow()
    
    # Segment name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(segment_data[0])))
    row.addElement(cell)
    
    # Distance, elevation gain, elevation loss (float)
    for value in segment_data[1:]:
        cell = TableCell(valuetype="float", value=str(value))
        cell.addElement(P(text=str(value)))
        row.addElement(cell)
    
    # Add 4 empty cells for formulas (columns E-H)
    for _ in range(4):
        cell = TableCell()
        row.addElement(cell)
    
    table.addElement(row)

# Add empty row
empty_row = TableRow()
for _ in range(8):
    empty_row.addElement(TableCell())
table.addElement(empty_row)

# Add summary section
summary_labels = [
    "",
    "Total Moving Time (hours):",
    "Safety Margin (25%):",
    "Total Time with Margin:",
    "",
    "Available Daylight (hours):",
    "Hike Feasible?:",
    "Latest Start Time:"
]

for label_text in summary_labels:
    row = TableRow()
    
    # Label cell
    cell = TableCell(valuetype="string")
    if label_text:
        cell.addElement(P(text=label_text))
    row.addElement(cell)
    
    # Value cell (empty for now, or pre-filled for Available Daylight)
    if label_text == "Available Daylight (hours):":
        cell = TableCell(valuetype="float", value="10")
        cell.addElement(P(text="10"))
        row.addElement(cell)
    else:
        row.addElement(TableCell())
    
    # Add empty cells
    for _ in range(6):
        row.addElement(TableCell())
    
    table.addElement(row)

# Add instructions section
instruction_row = TableRow()
instruction_cell = TableCell(valuetype="string", numbercolumnsspanned="8")
instruction_cell.addElement(P(text=""))
instruction_row.addElement(instruction_cell)
table.addElement(instruction_row)

instruction_row = TableRow()
instruction_cell = TableCell(valuetype="string", numbercolumnsspanned="8")
instruction_cell.addElement(P(text="INSTRUCTIONS: Calculate hiking times using Naismith's Rule"))
instruction_row.addElement(instruction_cell)
table.addElement(instruction_row)

instruction_row = TableRow()
instruction_cell = TableCell(valuetype="string", numbercolumnsspanned="8")
instruction_cell.addElement(P(text="Base Time (E) = Distance/5 | Ascent Time (F) = ElevGain/600 | Descent Bonus (G) = -ElevLoss/1200 | Total (H) = E+F+G"))
instruction_row.addElement(instruction_cell)
table.addElement(instruction_row)

# Add table to document
doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/hiking_calculator.ods")
print("✅ Created hiking_calculator.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/hiking_calculator.ods
sudo chmod 644 /home/ga/Documents/hiking_calculator.ods

echo "✅ Created trail data file"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/hiking_calculator.ods > /tmp/calc_hiking_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_hiking_task.log || true
    # Don't exit, continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue anyway
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

# Position cursor at cell E2 (first formula cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Hiking Time Calculator Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Use Naismith's Rule to calculate hiking times:"
echo ""
echo "1. Column E (Base Time): =B2/5 (hours to hike distance)"
echo "2. Column F (Ascent Time): =C2/600 (penalty for climbing)"
echo "3. Column G (Descent Bonus): =-D2/1200 (bonus for descending)"
echo "4. Column H (Total): =E2+F2+G2 (total segment time)"
echo "5. Copy formulas down to row 8 (all 7 segments)"
echo ""
echo "6. Total Moving Time (B10): =SUM(H2:H8)"
echo "7. Safety Margin (B11): =B10*0.25"
echo "8. Total with Margin (B12): =B10+B11"
echo "9. Hike Feasible (B14): =IF(B12<=B13,\"YES - SAFE\",\"NO - TOO LONG\")"
echo ""
echo "Expected result: ~5.75 hours total, SAFE for 10-hour daylight"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"