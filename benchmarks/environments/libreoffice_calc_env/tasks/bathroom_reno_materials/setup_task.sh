#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Bathroom Renovation Materials Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the renovation materials spreadsheet with Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Renovation Materials"
table = Table(name="Renovation Materials")
doc.spreadsheet.addElement(table)

# Header row
header_data = [
    "Item Name", "Length", "Width", "Unit", "Waste Factor %", 
    "Coverage per Package (sq ft)", "Price per Package", "Budget Limit",
    "Area Sq Ft", "Adjusted Sq Ft", "Packages Needed", "Total Cost", "Budget Status"
]

header_row = TableRow()
for header_text in header_data:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Data rows with mixed units and missing waste factors
data_rows = [
    ["Floor Tile (Porcelain)", 5.25, 4.67, "decimal ft", None, 12, 42.99, 500, "", "", "", "", ""],
    ["Wall Tile (Subway)", 8.5, 6.25, "decimal ft", 10, 11, 38.50, 400, "", "", "", "", ""],
    ["Waterproof Membrane", 160, 142, "cm", None, 107.64, 89.99, 200, "", "", "", "", ""],
    ["Paint (Waterproof)", 8, 6, "decimal ft", 5, 350, 31.99, 100, "", "", "", "", ""],
    ["Tile Adhesive", 5.25, 4.75, "decimal ft", None, 50, 28.50, 150, "", "", "", "", ""],
    ["Grout", 5.25, 4.75, "decimal ft", 10, 100, 19.99, 150, "", "", "", "", ""]
]

for row_data in data_rows:
    row = TableRow()
    for i, value in enumerate(row_data):
        if value is None or value == "":
            # Empty cell
            cell = TableCell()
        elif isinstance(value, str):
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=value))
        elif isinstance(value, float):
            cell = TableCell(valuetype="float", value=value)
            cell.addElement(P(text=str(value)))
        elif isinstance(value, int):
            cell = TableCell(valuetype="float", value=float(value))
            cell.addElement(P(text=str(value)))
        else:
            cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Add empty rows for Grand Total section
for _ in range(2):
    row = TableRow()
    for _ in range(len(header_data)):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Grand Total label row
total_row = TableRow()
total_label_cell = TableCell(valuetype="string")
total_label_cell.addElement(P(text="TOTAL PROJECT COST:"))
total_row.addElement(total_label_cell)
for _ in range(len(header_data) - 1):
    cell = TableCell()
    total_row.addElement(cell)
table.addElement(total_row)

# Add more empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(len(header_data)):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/bathroom_reno_materials.ods"
doc.save(output_path)
print(f"Created renovation materials spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/bathroom_reno_materials.ods
sudo chmod 666 /home/ga/Documents/bathroom_reno_materials.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/bathroom_reno_materials.ods > /tmp/calc_reno_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_reno_task.log || true
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

# Position cursor at first calculation column (I2 - Area Sq Ft)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to column I (Area Sq Ft), row 2
safe_xdotool ga :1 key ctrl+g
sleep 0.5
safe_xdotool ga :1 type "I2"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Bathroom Renovation Materials Calculator Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: Sarah's bathroom renovation needs material calculations"
echo ""
echo "✅ Spreadsheet loaded with renovation data"
echo ""
echo "📝 YOUR TASKS:"
echo "  1. Calculate 'Area Sq Ft' (column I) - convert all units to square feet"
echo "     • decimal ft: multiply Length × Width"
echo "     • cm: convert to feet (÷ 30.48), then multiply Length × Width"
echo ""
echo "  2. Fill in missing 'Waste Factor %' (column E)"
echo "     • Typical values: 10-15% for tile, 5-10% for other materials"
echo ""
echo "  3. Calculate 'Adjusted Sq Ft' (column J)"
echo "     • Formula: Area Sq Ft × (1 + Waste Factor % / 100)"
echo ""
echo "  4. Calculate 'Packages Needed' (column K)"
echo "     • Formula: ROUNDUP(Adjusted Sq Ft / Coverage per Package, 0)"
echo "     • Must round UP (can't buy partial boxes)"
echo ""
echo "  5. Calculate 'Total Cost' (column L)"
echo "     • Formula: Packages Needed × Price per Package"
echo ""
echo "  6. Add 'Budget Status' (column M)"
echo "     • Formula: IF(Total Cost > Budget Limit, \"OVER BUDGET\", \"OK\")"
echo ""
echo "  7. Calculate Grand Total in row 9 or 10"
echo "     • SUM of all Total Cost values"
echo ""
echo "💡 HINTS:"
echo "  • Cursor is positioned at I2 (first Area Sq Ft cell)"
echo "  • 1 meter = 3.28084 feet, so 1 cm = 1/30.48 feet"
echo "  • Use ROUNDUP function, not ROUND (always round up for packages)"
echo "  • Budget flags help identify which items to reconsider"