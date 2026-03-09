#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Energy Tracker Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for creating ODS file)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true
fi

# Create the energy tracking spreadsheet with Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, ParagraphProperties
from odf.number import NumberStyle, Number, Text as NumText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet
table = Table(name="Energy Usage")

# Helper function to create a cell with value
def create_cell(value=None, formula=None, value_type='string'):
    cell = TableCell(valuetype=value_type)
    if formula:
        cell.setAttribute('formula', formula)
    if value is not None:
        p = P()
        p.addText(str(value))
        cell.addElement(p)
        if value_type == 'float':
            cell.setAttribute('value', str(value))
    return cell

# Header row
row = TableRow()
row.addElement(create_cell("Month"))
row.addElement(create_cell("Meter Reading"))
row.addElement(create_cell("kWh Used"))
row.addElement(create_cell("Cost ($)"))
row.addElement(create_cell("Prev Year kWh"))
row.addElement(create_cell("Change %"))
row.addElement(create_cell())  # Empty column G
table.addElement(row)

# Data rows with realistic meter readings
months = ["Jan 2024", "Feb 2024", "Mar 2024", "Apr 2024", "May 2024", "Jun 2024",
          "Jul 2024", "Aug 2024", "Sep 2024", "Oct 2024", "Nov 2024", "Dec 2024"]
meter_readings = [15280, 15750, 16240, 16720, 17100, 17680, 18420, 19210, 19810, 20340, 20820, 21400]
prev_year_kwh = [520, 485, 610, 450, 425, 620, 780, 820, 650, 560, 505, 615]

for i, (month, reading, prev_kwh) in enumerate(zip(months, meter_readings, prev_year_kwh)):
    row = TableRow()
    
    # Month
    row.addElement(create_cell(month))
    
    # Meter Reading
    row.addElement(create_cell(reading, value_type='float'))
    
    # kWh Used (empty - agent fills formula)
    row.addElement(create_cell())
    
    # Cost (empty - agent fills formula)
    row.addElement(create_cell())
    
    # Previous Year kWh
    row.addElement(create_cell(prev_kwh, value_type='float'))
    
    # Change % (empty - agent fills formula)
    row.addElement(create_cell())
    
    # Empty column for spacing
    row.addElement(create_cell())
    
    table.addElement(row)

# Add rate and base fee in column G (offset rows to align with data)
# Add empty row first
empty_row = TableRow()
for _ in range(7):
    empty_row.addElement(create_cell())
table.addElement(empty_row)

# Rate per kWh row (row 14, which is index 13 after header)
rate_row = TableRow()
for _ in range(6):
    rate_row.addElement(create_cell())
rate_row.addElement(create_cell("Rate ($/kWh)"))
rate_row.addElement(create_cell(0.14, value_type='float'))
table.addElement(rate_row)

# Base fee row
fee_row = TableRow()
for _ in range(6):
    fee_row.addElement(create_cell())
fee_row.addElement(create_cell("Base Fee ($)"))
fee_row.addElement(create_cell(12, value_type='float'))
table.addElement(fee_row)

# Summary section (after some spacing)
for _ in range(2):
    empty_row = TableRow()
    for _ in range(8):
        empty_row.addElement(create_cell())
    table.addElement(empty_row)

# Summary labels and empty cells for formulas
summaries = [
    "Total Annual kWh:",
    "Total Annual Cost:",
    "Average Monthly kWh:",
    "Highest Usage (kWh):",
    "Avg YoY Change %:"
]

for summary_label in summaries:
    summary_row = TableRow()
    summary_row.addElement(create_cell(summary_label))
    summary_row.addElement(create_cell())  # Empty cell for agent's formula
    for _ in range(6):
        summary_row.addElement(create_cell())
    table.addElement(summary_row)

# Add more empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        row.addElement(create_cell())
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/energy_tracker.ods")
print("Created energy tracker spreadsheet successfully")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/energy_tracker.ods
sudo chmod 666 /home/ga/Documents/energy_tracker.ods

echo "✅ Created energy tracking spreadsheet with meter readings"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/energy_tracker.ods > /tmp/calc_energy_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_energy_task.log || true
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

# Move cursor to cell C2 (first kWh calculation cell)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right
sleep 0.2

echo "=== Home Energy Tracker Task Setup Complete ==="
echo ""
echo "📊 Energy Tracking Spreadsheet Ready"
echo ""
echo "📝 Required Formulas:"
echo "  Column C (kWh Used): =B3-B2, =B4-B3, ... (current - previous reading)"
echo "  Column D (Cost): =(C2*\$G\$2)+\$G\$3 (kWh × rate + base fee)"
echo "  Column F (Change %): =(C2-E2)/E2*100 (percentage vs. last year)"
echo "  Summary section: Use SUM, AVERAGE, MAX functions"
echo ""
echo "💡 Tips:"
echo "  - Start with Column C (row 2 will be 0 or empty, start formulas at C3)"
echo "  - Use \$G\$2 and \$G\$3 for rate/fee (absolute references)"
echo "  - Copy formulas down after entering the first one"
echo "  - Summary formulas: SUM(C2:C13), AVERAGE(C2:C13), MAX(C2:C13)"