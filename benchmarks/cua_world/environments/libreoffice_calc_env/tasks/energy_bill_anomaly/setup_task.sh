#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Energy Bill Analysis Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create a proper blank ODS file using Python
echo "Creating blank spreadsheet..."
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
for _ in range(30):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/energy_analysis.ods")
print("Created blank ODS file successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/energy_analysis.ods
sudo chmod 666 /home/ga/Documents/energy_analysis.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/energy_analysis.ods > /tmp/calc_energy_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_energy_task.log || true
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

echo "=== Energy Bill Analysis Task Setup Complete ==="
echo ""
echo "📊 SCENARIO: You received a shockingly high electricity bill!"
echo "📋 TASK: Analyze the past 6 months to identify the problem month"
echo ""
echo "📝 Instructions:"
echo "  1. Create headers in Row 1:"
echo "     A1: Month | B1: kWh Usage | C1: Total Cost | D1: Cost per kWh | E1: % vs Average"
echo ""
echo "  2. Enter 6 months of data (rows 2-7):"
echo "     January:  850 kWh,  \$102.00"
echo "     February: 780 kWh,  \$93.60"
echo "     March:    820 kWh,  \$98.40"
echo "     April:    890 kWh,  \$106.80"
echo "     May:      1420 kWh, \$170.40  ← ANOMALY!"
echo "     June:     810 kWh,  \$97.20"
echo ""
echo "  3. Calculate Cost per kWh (Column D): =C2/B2 (copy down)"
echo ""
echo "  4. Calculate Average Usage: =AVERAGE(B2:B7) in B9 or nearby"
echo ""
echo "  5. Calculate % vs Average (Column E): =(B2-\$B\$9)/\$B\$9*100 (copy down)"
echo ""
echo "  6. Highlight the anomalous month (May, Row 6) with background color"
echo ""
echo "💡 TIP: May should show ~53% above average!"