#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Quilting Fabric Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the template spreadsheet with fabric data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Fabric Calculator"
table = Table(name="Fabric Calculator")
doc.spreadsheet.addElement(table)

# Define header row
headers = [
    "Fabric Color/Pattern",
    "Blocks Needed",
    "Block Width (in)",
    "Block Height (in)",
    "Directional?",
    "Total Sq Inches",
    "Raw Yards",
    "Yards + Safety",
    "Yards to Purchase"
]

# Add header row
header_row = TableRow()
for header_text in headers:
    cell = TableCell(valuetype="string")
    p = P(text=header_text)
    cell.addElement(p)
    header_row.addElement(cell)
table.addElement(header_row)

# Sample fabric data: [name, blocks, width, height, directional]
fabric_data = [
    ["Blue Floral", 12, 8, 8, "NO"],
    ["Red Stripe", 8, 10, 6, "YES"],
    ["Green Solid", 20, 5, 5, "NO"],
    ["Yellow Paisley", 6, 12, 10, "YES"],
    ["White Background", 30, 8, 8, "NO"],
    ["Purple Dots", 15, 6, 6, "NO"]
]

# Add data rows
for fabric in fabric_data:
    row = TableRow()
    
    # Fabric name (string)
    cell = TableCell(valuetype="string")
    p = P(text=str(fabric[0]))
    cell.addElement(p)
    row.addElement(cell)
    
    # Blocks needed (float)
    cell = TableCell(valuetype="float", value=str(fabric[1]))
    p = P(text=str(fabric[1]))
    cell.addElement(p)
    row.addElement(cell)
    
    # Block width (float)
    cell = TableCell(valuetype="float", value=str(fabric[2]))
    p = P(text=str(fabric[2]))
    cell.addElement(p)
    row.addElement(cell)
    
    # Block height (float)
    cell = TableCell(valuetype="float", value=str(fabric[3]))
    p = P(text=str(fabric[3]))
    cell.addElement(p)
    row.addElement(cell)
    
    # Directional (string)
    cell = TableCell(valuetype="string")
    p = P(text=str(fabric[4]))
    cell.addElement(p)
    row.addElement(cell)
    
    # Add empty cells for formulas (F, G, H, I)
    for _ in range(4):
        cell = TableCell()
        row.addElement(cell)
    
    table.addElement(row)

# Add some empty rows at the end
for _ in range(10):
    row = TableRow()
    for _ in range(len(headers)):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/quilt_fabric_plan.ods")
print("Created quilt fabric calculator template")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/quilt_fabric_plan.ods
sudo chmod 666 /home/ga/Documents/quilt_fabric_plan.ods

echo "✅ Created template: /home/ga/Documents/quilt_fabric_plan.ods"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/quilt_fabric_plan.ods > /tmp/calc_quilt_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_quilt_task.log || true
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

# Move cursor to cell F2 (first formula cell)
echo "Positioning cursor at F2..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.3

echo "=== Quilting Fabric Calculator Task Setup Complete ==="
echo ""
echo "📝 Task Instructions:"
echo "  Column F: Calculate total square inches (Blocks × Width × Height)"
echo "  Column G: Calculate raw yards needed"
echo "            - Non-directional: Total Sq In ÷ 1512 (42\" width × 36\"/yard)"
echo "            - Directional: Blocks × Height ÷ 36"
echo "            - Hint: Use IF(E2=\"YES\", B2*D2/36, F2/1512)"
echo "  Column H: Add 10% safety margin (Raw Yards × 1.10)"
echo "  Column I: Round up to 1/8 yard (use CEILING function)"
echo ""
echo "💡 Formula Tips:"
echo "  - Start with F2: =B2*C2*D2"
echo "  - Then G2: =IF(E2=\"YES\", B2*D2/36, F2/1512)"
echo "  - Then H2: =G2*1.10"
echo "  - Then I2: =CEILING(H2, 0.125)"
echo "  - Copy formulas down to all fabric rows"