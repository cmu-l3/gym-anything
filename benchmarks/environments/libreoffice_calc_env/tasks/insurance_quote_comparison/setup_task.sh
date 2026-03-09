#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Insurance Quote Comparison Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a proper blank ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Add empty rows to make it a proper spreadsheet
for _ in range(30):
    row = TableRow()
    for _ in range(15):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/insurance_comparison.ods")
print("Created blank ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/insurance_comparison.ods
sudo chmod 666 /home/ga/Documents/insurance_comparison.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/insurance_comparison.ods > /tmp/calc_insurance_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_insurance_task.log
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Insurance Quote Comparison Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a comparison table with:"
echo "  - Headers: Provider, Liability (Monthly), Comprehensive (Semi-annual), Collision (Annual), Total Annual Cost"
echo "  - Row 1: SafeDrive Insurance: \$85/mo, \$320/semi, \$450/annual"
echo "  - Row 2: QuickQuote Auto: \$78/mo, \$340/semi, \$475/annual"
echo "  - Row 3: BudgetShield Cars: \$92/mo, \$295/semi, \$425/annual"
echo "  - Create formulas to convert to annual: (monthly×12) + (semi×2) + annual"
echo "  - Apply conditional formatting to highlight cheapest total"
echo ""
echo "💡 Expected totals:"
echo "  - SafeDrive: \$2,110/year"
echo "  - QuickQuote: \$2,091/year (cheapest)"
echo "  - BudgetShield: \$2,119/year"