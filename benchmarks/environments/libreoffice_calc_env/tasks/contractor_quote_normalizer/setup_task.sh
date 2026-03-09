#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Contractor Quote Normalizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create messy contractor quotes spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create table
table = Table(name="Contractor Quotes")

# Header explaining the task
rows_data = [
    ["ROOF REPAIR CONTRACTOR QUOTES - COMPARISON NEEDED"],
    ["You received 3 quotes in different formats. Normalize them to compare fairly."],
    [""],
    ["========== CONTRACTOR A - SMITH ROOFING (Itemized) =========="],
    ["Item", "Cost"],
    ["Labor (tear-off and installation)", "$1,200"],
    ["Asphalt shingles (30 bundles)", "$450"],
    ["Underlayment material", "$120"],
    ["Flashing replacement", "$80"],
    ["Debris disposal fee", "$75"],
    ["TOTAL (Contractor A)", "$1,925"],
    ["NOTE: Does NOT include permit fees"],
    [""],
    ["========== CONTRACTOR B - QUICK FIX ROOFS (Bundled) =========="],
    ["Service", "Price"],
    ["Complete tear-off and installation package", "$1,950"],
    ["  (includes all materials, labor, cleanup, permit)", ""],
    ["Gutter repair (OPTIONAL add-on)", "$200"],
    [""],
    ["========== CONTRACTOR C - JOE'S ROOFING (Mixed format) =========="],
    ["Description", "Amount"],
    ["Roofing material (shingles & felt)", "$380"],
    ["Labor for installation", "$900"],
    ["Flashing and trim work", "$150"],
    ["Optional: New ridge vent installation", "$180"],
    ["Optional: Gutter cleaning service", "$100"],
    ["Base total (required work only)", "$1,430"],
    ["Total with all options", "$1,710"],
    [""],
    ["========== YOUR TASK =========="],
    ["1. Create standardized categories (Materials, Labor, Permits, Optional)"],
    ["2. Map each contractor's items to these categories"],
    ["3. Calculate 'Required Work Only' totals for fair comparison"],
    ["4. Use formulas to identify the lowest cost contractor"],
    ["5. Flag outlier pricing (items that are >30% different from average)"],
    ["6. Create a summary section showing which contractor offers best value"],
]

# Add rows
for row_data in rows_data:
    row = TableRow()
    for cell_value in row_data:
        cell = TableCell()
        p = P(text=str(cell_value))
        cell.addElement(p)
        row.addElement(cell)
    table.addElement(row)

# Add empty rows for workspace
for _ in range(30):
    row = TableRow()
    for _ in range(15):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save
doc.save("/home/ga/Documents/contractor_quotes.ods")
print("✅ Created contractor quotes spreadsheet")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/contractor_quotes.ods
sudo chmod 666 /home/ga/Documents/contractor_quotes.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/contractor_quotes.ods > /tmp/calc_contractor_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_contractor_task.log || true
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

# Position cursor below the task description
safe_xdotool ga :1 key ctrl+End
sleep 0.3

echo "=== Contractor Quote Normalizer Task Setup Complete ==="
echo "📝 Task: Normalize 3 messy contractor quotes into standardized comparison"
echo "💡 Tips:"
echo "   - Create standard categories: Materials, Labor, Permits, Optional"
echo "   - Use SUM formulas for totals"
echo "   - Apply conditional formatting to highlight outliers"
echo "   - Build a summary comparison section"
echo "   - Identify the best value contractor with MIN formula"