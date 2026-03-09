#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Streaming Service Subscription Audit Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create ODS file with subscription data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, CurrencySymbol, Number, Text as NumberText
import datetime

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Sheet1"
table = Table(name="Sheet1")

# Header row
header_row = TableRow()
headers = ["Service Name", "Cost", "Billing Cycle", "Renewal Date", "Shared With", "Hours Watched/Month"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Calculate dates relative to today for realistic renewal dates
today = datetime.date.today()
date_15_days = today + datetime.timedelta(days=15)
date_25_days = today + datetime.timedelta(days=25)
date_45_days = today + datetime.timedelta(days=45)
date_60_days = today + datetime.timedelta(days=60)
date_90_days = today + datetime.timedelta(days=90)

# Data rows - realistic streaming services with varied data
data_rows = [
    ["Netflix", 15.99, "Monthly", date_45_days.strftime("%Y-%m-%d"), "", 25],
    ["Disney+", 79.99, "Annual", date_90_days.strftime("%Y-%m-%d"), "", 12],
    ["HBO Max", 15.99, "Monthly", date_15_days.strftime("%Y-%m-%d"), "Sarah", 8],
    ["Spotify Premium", 10.99, "Monthly", date_60_days.strftime("%Y-%m-%d"), "", 40],
    ["YouTube Premium", 11.99, "Monthly", date_25_days.strftime("%Y-%m-%d"), "Roommate", 15],
    ["Hulu", 7.99, "Monthly", date_90_days.strftime("%Y-%m-%d"), "", 0],
    ["Apple TV+", 99.99, "Annual", date_45_days.strftime("%Y-%m-%d"), "", 5],
    ["Amazon Prime", 139.00, "Annual", date_25_days.strftime("%Y-%m-%d"), "Family", 20],
]

for row_data in data_rows:
    row = TableRow()
    
    # Service Name (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(row_data[0])))
    row.addElement(cell)
    
    # Cost (float)
    cell = TableCell(valuetype="float", value=str(row_data[1]))
    cell.addElement(P(text=str(row_data[1])))
    row.addElement(cell)
    
    # Billing Cycle (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=row_data[2]))
    row.addElement(cell)
    
    # Renewal Date (date)
    cell = TableCell(valuetype="date", datevalue=row_data[3])
    cell.addElement(P(text=row_data[3]))
    row.addElement(cell)
    
    # Shared With (string, may be empty)
    cell = TableCell(valuetype="string")
    if row_data[4]:
        cell.addElement(P(text=row_data[4]))
    row.addElement(cell)
    
    # Hours Watched/Month (float)
    cell = TableCell(valuetype="float", value=str(row_data[5]))
    cell.addElement(P(text=str(row_data[5])))
    row.addElement(cell)
    
    table.addElement(row)

# Add empty rows for formulas (columns G onwards will be added by agent)
for _ in range(5):
    row = TableRow()
    for _ in range(15):  # Extra columns for calculated fields
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/streaming_subscriptions.ods")
print("✅ Created streaming_subscriptions.ods with subscription data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/streaming_subscriptions.ods
sudo chmod 666 /home/ga/Documents/streaming_subscriptions.ods

# Verify file was created
if [ -f "/home/ga/Documents/streaming_subscriptions.ods" ]; then
    echo "✅ Subscription data file created successfully"
    ls -lh /home/ga/Documents/streaming_subscriptions.ods
else
    echo "❌ ERROR: Failed to create subscription data file"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/streaming_subscriptions.ods > /tmp/calc_streaming_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_streaming_task.log || true
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

# Position cursor at cell G1 (first empty column for calculated fields)
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
safe_xdotool ga :1 key Right Right Right Right Right Right
sleep 0.3

echo "=== Streaming Subscription Audit Task Setup Complete ==="
echo ""
echo "📊 Task Overview:"
echo "   8 streaming subscriptions with mixed billing cycles"
echo ""
echo "📝 Required Actions:"
echo "   1. Add 'Monthly Cost' column - normalize annual to monthly (=IF(C2=\"Annual\", B2/12, B2))"
echo "   2. Add 'Days to Renewal' column - calculate days remaining (=D2-TODAY())"
echo "   3. Add 'Renewal Alert' column - flag if renewing soon (=IF([Days]<=30, \"RENEWING SOON\", \"\"))"
echo "   4. Add 'Cost/Hour' column - calculate value (=IF(F2=0, \"Not Used\", [Monthly]/F2))"
echo "   5. Add 'Amount Owed' column - calculate shared splits (=IF(E2<>\"\", [Monthly]/2, 0))"
echo "   6. Create total row or cells for monthly cost and amounts owed"
echo ""
echo "💡 Tips:"
echo "   - Some subscriptions are Annual (need ÷12), some Monthly (keep as-is)"
echo "   - Some renewal dates are within 30 days (need alert)"
echo "   - Some services have 0 hours watched (handle division by zero)"
echo "   - Some services are shared (calculate 50% owed)"
echo "   - Copy formulas down to all 8 data rows (rows 2-9)"