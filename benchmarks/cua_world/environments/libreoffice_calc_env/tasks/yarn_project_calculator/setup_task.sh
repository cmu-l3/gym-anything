#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Yarn Project Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing python3-odf..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the 3-sheet workbook with pre-populated data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# ===== Pattern_Specs Sheet =====
pattern_table = Table(name="Pattern_Specs")

# Header row
header_row = TableRow()
for header in ["Size", "Total Yardage", "Gauge (st/in)"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
pattern_table.addElement(header_row)

# Data rows
pattern_data = [
    ["Small", 1200, 5.5],
    ["Medium", 1400, 5.5],
    ["Large", 1650, 5.5]
]

for row_data in pattern_data:
    row = TableRow()
    # Size (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(row_data[0])))
    row.addElement(cell)
    # Yardage (number)
    cell = TableCell(valuetype="float", value=str(row_data[1]))
    cell.addElement(P(text=str(row_data[1])))
    row.addElement(cell)
    # Gauge (number)
    cell = TableCell(valuetype="float", value=str(row_data[2]))
    cell.addElement(P(text=str(row_data[2])))
    row.addElement(cell)
    pattern_table.addElement(row)

doc.spreadsheet.addElement(pattern_table)

# ===== Yarn_Options Sheet =====
yarn_table = Table(name="Yarn_Options")

# Header row
header_row = TableRow()
for header in ["Yarn Name", "Fiber", "Yards/Skein", "Price/Skein", "Color Options"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
yarn_table.addElement(header_row)

# Data rows
yarn_data = [
    ["Cozy Wool", "100% Wool", 220, 8.50, 45],
    ["Budget Acrylic", "Acrylic", 280, 4.99, 30],
    ["Luxury Blend", "Wool/Silk", 200, 12.00, 20]
]

for row_data in yarn_data:
    row = TableRow()
    # Yarn Name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(row_data[0])))
    row.addElement(cell)
    # Fiber (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(row_data[1])))
    row.addElement(cell)
    # Yards/Skein (number)
    cell = TableCell(valuetype="float", value=str(row_data[2]))
    cell.addElement(P(text=str(row_data[2])))
    row.addElement(cell)
    # Price/Skein (number)
    cell = TableCell(valuetype="float", value=str(row_data[3]))
    cell.addElement(P(text=str(row_data[3])))
    row.addElement(cell)
    # Color Options (number)
    cell = TableCell(valuetype="float", value=str(row_data[4]))
    cell.addElement(P(text=str(row_data[4])))
    row.addElement(cell)
    yarn_table.addElement(row)

doc.spreadsheet.addElement(yarn_table)

# ===== Calculations Sheet (template) =====
calc_table = Table(name="Calculations")

# Structure with headers
calc_structure = [
    ["Yarn Comparison Calculator", "", "", ""],
    ["", "", "", ""],
    ["Selected Size:", "Medium", "", ""],
    ["Base Yardage Needed:", "", "", ""],
    ["Adjusted Yardage (15% safety margin):", "", "", ""],
    ["", "", "", ""],
    ["Option A: Cozy Wool", "Option B: Budget Acrylic", "Option C: Luxury Blend", ""],
    ["Skeins Needed:", "", "", ""],
    ["Total Cost:", "", "", ""],
    ["", "", "", ""],
    ["=== SHOPPING LIST ===", "", "", ""],
    ["Best Option:", "", "", ""],
    ["Yarn Name:", "", "", ""],
    ["Skeins to Buy:", "", "", ""],
    ["Cost per Skein:", "", "", ""],
    ["Total Cost:", "", "", ""],
]

for row_data in calc_structure:
    row = TableRow()
    for cell_text in row_data:
        cell = TableCell(valuetype="string")
        if cell_text:
            cell.addElement(P(text=str(cell_text)))
        row.addElement(cell)
    calc_table.addElement(row)

# Add extra empty rows
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    calc_table.addElement(row)

doc.spreadsheet.addElement(calc_table)

# Save the file
output_path = "/home/ga/Documents/yarn_calculator.ods"
doc.save(output_path)
print(f"Created 3-sheet workbook: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/yarn_calculator.ods
sudo chmod 666 /home/ga/Documents/yarn_calculator.ods

echo "✅ Created yarn_calculator.ods with 3 sheets"
ls -lh /home/ga/Documents/yarn_calculator.ods

# Launch LibreOffice Calc with the workbook
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/yarn_calculator.ods > /tmp/calc_yarn_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_yarn_task.log || true
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
fi

# Click on center of screen to select desktop
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
        
        # Navigate to Calculations sheet (third sheet)
        # Use Ctrl+PageDown twice to move from first to third sheet
        echo "Navigating to Calculations sheet..."
        safe_xdotool ga :1 key ctrl+Page_Down
        sleep 0.3
        safe_xdotool ga :1 key ctrl+Page_Down
        sleep 0.3
        
        # Position cursor at B4 (where first formula should go)
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.2
        safe_xdotool ga :1 key Down Down Down
        sleep 0.2
        safe_xdotool ga :1 key Right
        sleep 0.2
    fi
fi

echo "=== Yarn Project Calculator Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "You are on the 'Calculations' sheet. Complete the following:"
echo ""
echo "1. Cell B4: Create formula to pull Medium size yardage from Pattern_Specs"
echo "   Example: =Pattern_Specs.B3"
echo ""
echo "2. Cell B5: Add 15% safety margin to base yardage"
echo "   Example: =B4*1.15"
echo ""
echo "3. Row 8 (Skeins Needed) for each yarn option:"
echo "   B8: =CEILING(B5/Yarn_Options.C2,1)  [Cozy Wool: 220 yards/skein]"
echo "   C8: =CEILING(B5/Yarn_Options.C3,1)  [Budget Acrylic: 280 yards/skein]"
echo "   D8: =CEILING(B5/Yarn_Options.C4,1)  [Luxury Blend: 200 yards/skein]"
echo ""
echo "4. Row 9 (Total Cost) for each yarn option:"
echo "   B9: =B8*Yarn_Options.D2  [skeins × price]"
echo "   C9: =C8*Yarn_Options.D3"
echo "   D9: =D8*Yarn_Options.D4"
echo ""
echo "5. Fill shopping list (rows 12-16) with best option details"
echo ""
echo "💡 TIPS:"
echo "   - CEILING always rounds UP (can't buy 4.3 skeins)"
echo "   - Cross-sheet references use SheetName.CellAddress"
echo "   - Compare costs in B9, C9, D9 to find cheapest"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"