#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Cost Per Use Analyzer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (needed for ODS creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create ODS file with pre-populated data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, CurrencyStyle, CurrencySymbol, Text as NumText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet named "Purchase Analysis"
table = Table(name="Purchase Analysis")

# Data for the task (Item Name, Purchase Price, Times Used)
data = [
    ["Item Name", "Purchase Price", "Times Used", "Cost Per Use", "Value Assessment"],
    ["Home Exercise Bike", 450, 12, "", ""],
    ["Bread Maker", 89, 3, "", ""],
    ["Running Shoes", 120, 200, "", ""],
    ["Specialty Kitchen Knife", 180, 450, "", ""],
    ["Gym Membership (annual)", 600, 8, "", ""],
    ["Formal Suit", 400, 2, "", ""],
    ["Power Drill", 85, 45, "", ""],
    ["Yoga Mat", 35, 180, "", ""],
    ["Streaming Service (annual)", 144, 200, "", ""],
    ["Camping Tent", 280, 0, "", ""],
    ["Coffee Maker", 120, 730, "", ""],
    ["Instant Pot", 99, 0, "", ""]
]

# Add rows to the table
for row_data in data:
    row = TableRow()
    for i, cell_value in enumerate(row_data):
        cell = TableCell()
        
        # Set cell value based on type
        if isinstance(cell_value, str):
            cell.setAttrNS(None, "office:value-type", "string")
            p = P(text=cell_value)
            cell.addElement(p)
        elif isinstance(cell_value, (int, float)):
            cell.setAttrNS(None, "office:value-type", "float")
            cell.setAttrNS(None, "office:value", str(cell_value))
            p = P(text=str(cell_value))
            cell.addElement(p)
        else:
            # Empty cell
            pass
        
        row.addElement(cell)
    table.addElement(row)

# Add some extra empty rows for formatting space
for _ in range(5):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
output_path = "/home/ga/Documents/cost_per_use_analysis.ods"
doc.save(output_path)
print(f"✅ Created ODS file: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/cost_per_use_analysis.ods
sudo chmod 666 /home/ga/Documents/cost_per_use_analysis.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/cost_per_use_analysis.ods > /tmp/calc_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
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

# Position cursor at cell D2 (Cost Per Use column, first data row)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right
sleep 0.2

echo "=== Cost Per Use Analyzer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. In column D (Cost Per Use), create formulas that divide Price by Times Used"
echo "  2. Use IFERROR or IF to handle division by zero: =IFERROR(B2/C2, 99999)"
echo "  3. In column E (Value Assessment), create IF formulas for categorization"
echo "  4. Apply currency formatting to columns B and D"
echo "  5. Apply conditional formatting to column D (color scale)"
echo "  6. Sort entire data range by Cost Per Use (column D) in descending order"
echo ""
echo "💡 Hints:"
echo "  - Items with 0 usage (Camping Tent, Instant Pot) should show 99999 or error text"
echo "  - Value categories: Excellent (<$1), Good (<$5), Poor (<$20), Waste (>=20)"
echo "  - Use Data → Sort to sort by column D descending"