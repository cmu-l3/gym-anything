#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Rebate Deadline Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install Python ODF library if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing python3-odf..."
# apt-get update -qq && apt-get install -y python3-odf 2>&1 | grep -v "^Get:" | grep -v "^Reading" || true
fi

# Create messy rebate tracking spreadsheet with intentional issues
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for currency (optional, cells can be unformatted too)
currency_style = NumberStyle(name="curr1")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces=0, minintegerdigits=1))
doc.styles.addElement(currency_style)

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")
doc.spreadsheet.addElement(table)

# Headers
headers = ["Product", "Purchase Date", "Rebate Amount", "Validity Period", "Deadline", "Days Remaining", "Status", "Notes"]
header_row = TableRow()
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Data with intentional messiness
rebate_data = [
    ["LG 65\" TV", "11/15/2024", "$150", "60", "01/14/2025", "", "Submitted", "Mailed 11/20"],
    ["HP Laptop", "12-01-2024", "75", "45", "", "", "sent", "Need to check"],
    ["Epson Printer", "12/10/2024", "$30.00", "30", "", "", "pending", "Find receipt"],
    ["Sony Headphones", "11/25/2024", "$50", "45", "01/09/2025", "", "MAILED", ""],
    ["Ring Doorbell", "12/15/2024", "40", "30", "", "", "Not yet", "Bought online"],
    ["Samsung Monitor", "10/30/2024", "60", "60", "12/29/2024", "", "pending", "URGENT!"],
    ["Gaming Mouse", "12/05/2024", "$25", "45", "", "", "", "Lost receipt?"],
    ["Smart Thermostat", "11/10/2024", "100", "45", "12/25/2024", "", "Submitted", ""],
    ["Xbox Controller", "12/18/2024", "20", "30", "", "", "pending", ""],
    ["LED Bulbs (6-pack)", "11/28/2024", "15", "60", "01/27/2025", "", "sent", ""]
]

for row_data in rebate_data:
    row = TableRow()
    for i, value in enumerate(row_data):
        if value == "":
            # Empty cell
            cell = TableCell()
        elif i == 3:  # Validity Period (number)
            cell = TableCell(valuetype="float", value=value)
            cell.addElement(P(text=value))
        else:
            # String cell
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=value))
        row.addElement(cell)
    table.addElement(row)

# Add some empty rows for totals
for _ in range(5):
    row = TableRow()
    for _ in range(8):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/rebate_tracker.ods")
print("Created messy rebate_tracker.ods successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/rebate_tracker.ods
sudo chmod 666 /home/ga/Documents/rebate_tracker.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/rebate_tracker.ods > /tmp/calc_rebate_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_rebate_task.log || true
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

echo "=== Rebate Deadline Tracker Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  🗓️  Clean inconsistent date formats"
echo "  ⏰ Calculate missing deadlines and days remaining"
echo "  📊 Standardize status field (Submitted/Pending/Expired)"
echo "  🎯 Add priority classification (URGENT/Soon/OK)"
echo "  🎨 Apply conditional formatting"
echo "  💰 Calculate financial totals (pending, at-risk, missed)"
echo "  📈 Sort by urgency and amount"
echo ""
echo "💡 Hints:"
echo "  - Use DATEVALUE() to convert text dates"
echo "  - Deadline = Purchase Date + Validity Period"
echo "  - Days Remaining = Deadline - TODAY()"
echo "  - Use nested IF for priority logic"
echo "  - SUMIF for category totals"