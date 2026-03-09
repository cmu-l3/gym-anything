#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Homebrew Recipe Scaler Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create recipe template ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText
from odf import number

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create a sheet
table = Table(name="Recipe")
doc.spreadsheet.addElement(table)

def add_row(values):
    """Helper to add a row with values"""
    row = TableRow()
    for val in values:
        cell = TableCell()
        if val is not None:
            p = P(text=str(val))
            cell.addElement(p)
            # Set value type
            if isinstance(val, (int, float)):
                cell.setAttribute('valuetype', 'float')
                cell.setAttribute('value', str(val))
            else:
                cell.setAttribute('valuetype', 'string')
        row.addElement(cell)
    table.addElement(row)

# Add header and recipe data
add_row(["Belgian Witbier - Recipe Scaler", None, None, None, None])
add_row(["Scale Factor:", None, None, "(Enter formula here: =3/5)", None])
add_row(["Original Batch:", "5 gallons", None, None, None])
add_row(["Target Batch:", "3 gallons", None, None, None])
add_row([None, None, None, None, None])  # Empty row

# Grain Bill Section
add_row(["GRAIN BILL", None, None, None, None])
add_row(["Ingredient", "Original (lbs)", "Scaled (lbs)", "Notes", None])
add_row(["Pilsner Malt", 6.5, None, "Base malt", None])
add_row(["Wheat Malt", 3.0, None, "30% of grain bill", None])
add_row(["Oats (flaked)", 0.5, None, "Mouthfeel", None])
add_row([None, None, None, None, None])  # Empty row

# Hop Schedule Section
add_row(["HOP SCHEDULE", None, None, None, None])
add_row(["Hop Variety", "Original (oz)", "Time (min)", "Scaled (oz)", None])
add_row(["Hallertau", 1.0, 60, None, None])
add_row(["Coriander", 0.75, 5, None, None])
add_row([None, None, None, None, None])  # Empty row

# Yeast & Other
add_row(["YEAST & ADDITIONS", None, None, None, None])
add_row(["Belgian Wit Yeast", 1, None, "packets", None])
add_row(["Orange Peel (dried)", 1.0, None, "oz", None])
add_row([None, None, None, None, None])  # Empty row

# Brewing Parameters
add_row(["EXPECTED PARAMETERS", None, None, None, None])
add_row(["Original Gravity (OG):", 1.048, None, None, None])
add_row(["Final Gravity (FG):", 1.010, None, None, None])
add_row(["Calculated ABV (%):", None, None, "(Enter formula: =(B20-B21)*131.25)", None])
add_row([None, None, None, None, None])

# Add empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/belgian_wit_recipe.ods"
doc.save(output_path)
print(f"✅ Created recipe template: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/belgian_wit_recipe.ods
sudo chmod 666 /home/ga/Documents/belgian_wit_recipe.ods

# Launch LibreOffice Calc with the recipe
echo "Launching LibreOffice Calc with recipe template..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/belgian_wit_recipe.ods > /tmp/calc_homebrew.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_homebrew.log || true
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

# Position cursor at scale factor cell (B2)
echo "Positioning cursor at scale factor cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Down
sleep 0.2
safe_xdotool ga :1 key Right
sleep 0.2

echo "=== Homebrew Recipe Scaler Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "  1. In cell B2, enter the scale factor formula: =3/5 (or =0.6)"
echo "  2. Scale grain amounts (C8:C10): =B8*\$B\$2, =B9*\$B\$2, =B10*\$B\$2"
echo "  3. Scale hop amounts (D14:D15): =B14*\$B\$2, =B15*\$B\$2"
echo "  4. Scale yeast/additions (C18:C19): formulas with absolute reference"
echo "  5. Calculate ABV in B22: =(B20-B21)*131.25"
echo ""
echo "💡 TIPS:"
echo "  - Use absolute reference (\$B\$2) for scale factor"
echo "  - ABV formula uses gravity values in B20 (OG) and B21 (FG)"
echo "  - Expected ABV result: ~4.99%"
echo "  - For discrete items, consider: =IF(B18*\$B\$2<1,1,ROUND(B18*\$B\$2,0))"