#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Band Gig Profit Splitter Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the pre-populated ODS file with gig data using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create main table for gig log
gig_table = Table(name="Gig_Log")
doc.spreadsheet.addElement(gig_table)

# Gig log data: Date, Venue, Revenue, Alex, Bailey, Casey, Drew (Y/N attendance)
gig_header = ["Date", "Venue", "Revenue", "Alex", "Bailey", "Casey", "Drew"]
gig_data = [
    ["2024-01-05", "The Rusty Nail", 350, "Y", "Y", "Y", "N"],
    ["2024-01-12", "Murphy's Pub", 280, "Y", "Y", "N", "Y"],
    ["2024-01-19", "Community Center", 450, "Y", "Y", "Y", "Y"],
    ["2024-01-26", "The Rusty Nail", 320, "N", "Y", "Y", "Y"],
    ["2024-02-02", "Bernie's Bar", 400, "Y", "Y", "Y", "N"],
    ["2024-02-09", "Street Fair", 180, "Y", "N", "Y", "Y"],
    ["2024-02-16", "Murphy's Pub", 300, "Y", "Y", "Y", "Y"],
    ["2024-02-23", "The Rusty Nail", 380, "Y", "Y", "N", "Y"]
]

# Add header row
header_row = TableRow()
for header in gig_header:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
gig_table.addElement(header_row)

# Add data rows
for row_data in gig_data:
    row = TableRow()
    for i, value in enumerate(row_data):
        if i == 2:  # Revenue column
            cell = TableCell(valuetype="float", value=str(value))
            cell.addElement(P(text=str(value)))
        else:
            cell = TableCell(valuetype="string")
            cell.addElement(P(text=str(value)))
        row.addElement(cell)
    gig_table.addElement(row)

# Add some empty rows for spacing
for _ in range(3):
    row = TableRow()
    for _ in range(7):
        cell = TableCell()
        row.addElement(cell)
    gig_table.addElement(row)

# Add Expense section header (row 13, 0-indexed row 12)
expense_header_row = TableRow()
expense_title_cell = TableCell(valuetype="string")
expense_title_cell.addElement(P(text="EXPENSES"))
expense_header_row.addElement(expense_title_cell)
for _ in range(6):
    expense_header_row.addElement(TableCell())
gig_table.addElement(expense_header_row)

# Expense headers
expense_cols = ["Expense Type", "Amount", "Frequency"]
expense_row_header = TableRow()
for col in expense_cols:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=col))
    expense_row_header.addElement(cell)
for _ in range(4):
    expense_row_header.addElement(TableCell())
gig_table.addElement(expense_row_header)

# Expense data
expenses = [
    ["PA System Rental", 75, "Per-Gig"],
    ["Gas/Transportation", 40, "Per-Gig"],
    ["Rehearsal Space", 200, "Monthly"],
    ["Website Hosting", 15, "Monthly"],
    ["Marketing/Flyers", 50, "Monthly"]
]

for expense in expenses:
    row = TableRow()
    cell1 = TableCell(valuetype="string")
    cell1.addElement(P(text=expense[0]))
    row.addElement(cell1)
    
    cell2 = TableCell(valuetype="float", value=str(expense[1]))
    cell2.addElement(P(text=str(expense[1])))
    row.addElement(cell2)
    
    cell3 = TableCell(valuetype="string")
    cell3.addElement(P(text=expense[2]))
    row.addElement(cell3)
    
    for _ in range(4):
        row.addElement(TableCell())
    gig_table.addElement(row)

# Add many empty rows for calculations
for _ in range(30):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    gig_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/band_finances.ods")
print("✅ Created band_finances.ods with gig log and expense data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/band_finances.ods
sudo chmod 666 /home/ga/Documents/band_finances.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/band_finances.ods > /tmp/calc_band_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_band_task.log || true
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

# Position cursor at a good starting point (below the data)
safe_xdotool ga :1 key ctrl+End
sleep 0.3

echo "=== Band Gig Profit Splitter Task Setup Complete ==="
echo ""
echo "📊 Gig Log Data:"
echo "  • 8 gigs from January-February 2024"
echo "  • Revenue ranges from \$180 to \$450 per gig"
echo "  • Member attendance marked with Y/N for Alex, Bailey, Casey, Drew"
echo ""
echo "💰 Expenses:"
echo "  • Per-Gig: PA rental (\$75), Gas (\$40)"
echo "  • Monthly: Rehearsal (\$200), Hosting (\$15), Marketing (\$50)"
echo ""
echo "📝 Your Task:"
echo "  1. Calculate Total Revenue (sum all gig revenue)"
echo "  2. Calculate Total Expenses (sum expenses, monthly × 2 months)"
echo "  3. Calculate Net Profit (revenue - expenses)"
echo "  4. Count each member's gig attendance (use COUNTIF for 'Y')"
echo "  5. Calculate Total Shares (sum of all attendance counts)"
echo "  6. Calculate Payment Per Share (net profit ÷ total shares)"
echo "  7. Calculate each member's payment (their gigs × payment per share)"
echo "  8. Verify: sum of individual payments should equal net profit"
echo ""
echo "💡 Hint: Create a summary section below the data with labeled calculations"