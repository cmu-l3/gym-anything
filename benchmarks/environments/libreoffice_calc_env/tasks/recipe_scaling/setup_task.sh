#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Scaling Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create pre-populated spreadsheet with recipe data
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Recipe data structure
recipe_data = [
    # Row 1: Original Yield
    ["Original Yield:", 24, "cookies", ""],
    # Row 2: Target Yield
    ["Target Yield:", 60, "cookies", ""],
    # Row 3: Empty
    ["", "", "", ""],
    # Row 4: Scaling Factor
    ["Scaling Factor:", "", "", ""],
    # Row 5: Empty
    ["", "", "", ""],
    # Row 6: Headers
    ["Ingredient", "Original Amount", "Unit", "Scaled Amount"],
    # Row 7-15: Ingredients
    ["All-Purpose Flour", 2, "cups", ""],
    ["Granulated Sugar", 1.5, "cups", ""],
    ["Brown Sugar", 0.75, "cups", ""],
    ["Butter", 8, "oz", ""],
    ["Eggs", 2, "whole", ""],
    ["Vanilla Extract", 2, "tsp", ""],
    ["Baking Soda", 1, "tsp", ""],
    ["Salt", 0.5, "tsp", ""],
    ["Chocolate Chips", 12, "oz", ""],
]

# Add rows to table
for row_data in recipe_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell()
        if cell_value != "":
            p = P()
            if isinstance(cell_value, (int, float)):
                # Set as numeric value
                cell.setAttrNS("urn:oasis:names:tc:opendocument:xmlns:office:1.0", "value-type", "float")
                cell.setAttrNS("urn:oasis:names:tc:opendocument:xmlns:office:1.0", "value", str(cell_value))
            p.addText(str(cell_value))
            cell.addElement(p)
        row.addElement(cell)
    table.addElement(row)

# Add extra empty rows for proper spreadsheet structure
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/recipe_scaling.ods"
doc.save(output_path)
print(f"Created recipe spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/recipe_scaling.ods
sudo chmod 666 /home/ga/Documents/recipe_scaling.ods

echo "✅ Recipe spreadsheet created"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/recipe_scaling.ods > /tmp/calc_recipe_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_recipe_task.log
    # Don't exit - continue anyway
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - continue anyway
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

# Position cursor at B4 (scaling factor cell) to give a hint
echo "Positioning cursor at scaling factor cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Navigate to B4
safe_xdotool ga :1 key Down Down Down  # Move to row 4
sleep 0.2
safe_xdotool ga :1 key Right  # Move to column B
sleep 0.2

echo "=== Recipe Scaling Task Setup Complete ==="
echo ""
echo "📝 Instructions:"
echo "  1. Calculate scaling factor in cell B4: =B2/B1"
echo "  2. Create formula in D7: =B7*\$B\$4"
echo "  3. Copy formula down to all ingredient rows (D7 through D15)"
echo "  4. Verify all scaled amounts are correct"
echo ""
echo "💡 Key concepts:"
echo "  - Use \$B\$4 (absolute reference) for scaling factor"
echo "  - Use B7, B8, etc. (relative reference) for ingredient amounts"
echo "  - Formula should be copied, not retyped for each row"