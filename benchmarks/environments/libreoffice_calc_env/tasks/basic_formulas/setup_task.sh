#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Basic Formulas Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a proper blank ODS file using Python
sudo apt-get update && sudo apt-get install -y python3-odf
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Add some empty rows to make it a proper spreadsheet
for _ in range(20):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/basic_formulas.ods")
print("Created blank ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/basic_formulas.ods
sudo chmod 666 /home/ga/Documents/basic_formulas.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/basic_formulas.ods > /tmp/calc_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
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

echo "=== Basic Formulas Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Enter values 10, 20, 30, 40, 50 in cells A1-A5"
echo "  2. In cell B1, enter: =SUM(A1:A5)"
echo "  3. In cell B2, enter: =AVERAGE(A1:A5)"
echo "  4. Verify results: B1 should show 150, B2 should show 30"
