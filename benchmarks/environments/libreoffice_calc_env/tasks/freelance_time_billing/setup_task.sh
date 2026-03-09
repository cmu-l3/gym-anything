#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Freelance Time Billing Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y python3-odf
fi

# Create timesheet with partial data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol
from decimal import Decimal
from datetime import time

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for currency and time
currency_style = CurrencyStyle(name="currency1")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces=2, minintegerdigits=1, grouping=True))
doc.styles.addElement(currency_style)

# Create table
table = Table(name="Timesheet")

# Add header row
header_row = TableRow()
headers = ["Date", "Client", "Project", "Start Time", "End Time", "Duration (hrs)", "Rate ($/hr)", "Amount ($)"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
table.addElement(header_row)

# Helper to create cell
def create_cell(value, value_type="string", formula=None):
    cell = TableCell(valuetype=value_type)
    if formula:
        cell.setAttribute("formula", formula)
    if value is not None:
        cell.addElement(P(text=str(value)))
    return cell

def create_time_cell(time_str):
    """Create a time cell (stored as decimal fraction of day)"""
    if not time_str or time_str == "-":
        return create_cell("", "string")
    
    # Parse time string like "9:00 AM" or "2:00 PM"
    time_str = time_str.strip()
    if "AM" in time_str or "PM" in time_str:
        is_pm = "PM" in time_str
        time_part = time_str.replace("AM", "").replace("PM", "").strip()
        if ":" in time_part:
            hour, minute = map(int, time_part.split(":"))
        else:
            hour = int(time_part)
            minute = 0
        
        if is_pm and hour != 12:
            hour += 12
        elif not is_pm and hour == 12:
            hour = 0
        
        # Convert to fraction of day
        time_value = (hour + minute/60.0) / 24.0
        
        cell = TableCell(valuetype="time", timevalue=f"PT{hour}H{minute}M00S", value=str(time_value))
        cell.addElement(P(text=time_str))
        return cell
    return create_cell(time_str, "string")

# Data entries
# Acme Corp entries
data_rows = [
    # Acme Corp
    ["1/15", "Acme Corp", "Website Redesign", "9:00 AM", "11:30 AM", None, 75, None],
    ["1/15", "Acme Corp", "Logo Design", "-", "-", 4.0, 75, None],
    ["1/16", "Acme Corp", "Bug Fixes", "2:00 PM", "4:00 PM", None, 75, None],
    # Acme subtotal placeholder
    ["", "", "Subtotal - Acme Corp", "", "", "", "", None],
    # TechStart Inc
    ["1/16", "TechStart Inc", "API Integration", "1:00 PM", "4:30 PM", None, 85, None],
    ["1/17", "TechStart Inc", "Database Setup", "-", "-", 2.5, 85, None],
    ["1/18", "TechStart Inc", "Code Review", "10:00 AM", "12:00 PM", None, 85, None],
    # TechStart subtotal placeholder
    ["", "", "Subtotal - TechStart Inc", "", "", "", "", None],
    # LocalBiz LLC
    ["1/18", "LocalBiz LLC", "Email Setup", "3:00 PM", "4:15 PM", None, 65, None],
    ["1/19", "LocalBiz LLC", "Training Session", "-", "-", 3.0, 65, None],
    # LocalBiz subtotal placeholder
    ["", "", "Subtotal - LocalBiz LLC", "", "", "", "", None],
    # Grand total placeholder
    ["", "", "GRAND TOTAL", "", "", "", "", None],
]

for row_data in data_rows:
    row = TableRow()
    
    for col_idx, value in enumerate(row_data):
        if col_idx == 3 or col_idx == 4:  # Start/End time columns
            cell = create_time_cell(value if value else "")
        elif col_idx == 5:  # Duration column
            if value is not None:
                cell = TableCell(valuetype="float", value=str(value))
                cell.addElement(P(text=str(value)))
            else:
                cell = TableCell()  # Empty cell for duration calculation
        elif col_idx == 6:  # Rate column
            if value:
                cell = TableCell(valuetype="float", value=str(value))
                cell.addElement(P(text=str(value)))
            else:
                cell = TableCell()
        elif col_idx == 7:  # Amount column
            cell = TableCell()  # Empty cell for amount calculation
        else:
            cell = create_cell(str(value) if value else "", "string")
        
        row.addElement(cell)
    
    table.addElement(row)

# Add empty rows
for _ in range(5):
    row = TableRow()
    for _ in range(8):
        row.addElement(TableCell())
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save
doc.save("/home/ga/Documents/freelance_timesheet.ods")
print("✅ Created timesheet with partial data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/freelance_timesheet.ods
sudo chmod 666 /home/ga/Documents/freelance_timesheet.ods

# Launch LibreOffice Calc with the timesheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/freelance_timesheet.ods > /tmp/calc_billing_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_billing_task.log || true
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

# Move cursor to cell F2 (first duration to calculate)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right
sleep 0.2
safe_xdotool ga :1 key Down
sleep 0.2

echo "=== Freelance Time Billing Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Calculate missing Durations from Start/End times: =(E-D)*24"
echo "  2. Calculate missing Amounts: Duration × Rate"
echo "  3. Create client subtotals using SUM formulas"
echo "  4. Calculate grand total"
echo "  5. Expected grand total: ~\$1593.75"
echo ""
echo "💡 Clients:"
echo "  - Acme Corp: \$75/hr (3 entries)"
echo "  - TechStart Inc: \$85/hr (3 entries)"
echo "  - LocalBiz LLC: \$65/hr (2 entries)"