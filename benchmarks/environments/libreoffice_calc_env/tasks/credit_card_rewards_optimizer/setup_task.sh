#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Credit Card Rewards Optimizer Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a blank ODS file using Python
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
doc.save("/home/ga/Documents/credit_card_optimizer.ods")
print("Created blank ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/credit_card_optimizer.ods
sudo chmod 666 /home/ga/Documents/credit_card_optimizer.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/credit_card_optimizer.ods > /tmp/calc_optimizer_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_optimizer_task.log || true
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

echo "=== Credit Card Rewards Optimizer Task Setup Complete ==="
echo ""
echo "📋 TASK: Build a credit card rewards optimizer"
echo ""
echo "📝 Instructions:"
echo "  1. Create a table with spending categories (Groceries, Gas, Dining, General)"
echo "  2. Add columns for monthly spending and cashback for 3 cards"
echo "  3. Card reward structures:"
echo "     • Card A: 3% groceries, 2% gas, 1% other"
echo "     • Card B: 2% dining, 2% gas, 1.5% other"
echo "     • Card C: 2% flat rate on everything"
echo "  4. Enter sample spending: Groceries \$600, Gas \$200, Dining \$300, General \$400"
echo "  5. Create formulas: Cashback = Spending × Reward Percentage"
echo "  6. Use MAX or IF functions to identify best card per category"
echo "  7. Add a 'Best Card' column with recommendations"
echo ""
echo "💡 Formula examples:"
echo "   • Cashback: =B2*0.03  (or =B2*3%)"
echo "   • Best Card: =IF(C2=MAX(C2:E2),\"Card A\",IF(D2=MAX(C2:E2),\"Card B\",\"Card C\"))"
echo ""