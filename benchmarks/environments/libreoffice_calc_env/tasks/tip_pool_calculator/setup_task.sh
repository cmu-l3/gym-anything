#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Tip Pool Calculator Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed (for creating ODS files)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create pre-filled ODS file with staff data and tip sources
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencyStyle, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create styles for currency formatting
currency_style = CurrencyStyle(name="currency1")
currency_style.addElement(CurrencySymbol(language="en", country="US", text="$"))
currency_style.addElement(Number(decimalplaces="2", minintegerdigits="1", grouping="true"))
doc.styles.addElement(currency_style)

# Add a sheet named "Tip Pool"
table = Table(name="Tip Pool")

# Row 1: Headers
header_row = TableRow()
headers = ["Name", "Hours Worked", "% of Hours", "Tip Share"]
for header_text in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header_text))
    header_row.addElement(cell)
table.addElement(header_row)

# Rows 2-6: Staff data (names and hours pre-filled, formulas empty)
staff_data = [
    ("Alice", 8.5),
    ("Bob", 6.0),
    ("Carlos", 7.5),
    ("Diana", 4.0),
    ("Emma", 5.5)
]

for name, hours in staff_data:
    row = TableRow()
    
    # Name cell
    name_cell = TableCell(valuetype="string")
    name_cell.addElement(P(text=name))
    row.addElement(name_cell)
    
    # Hours cell
    hours_cell = TableCell(valuetype="float", value=str(hours))
    hours_cell.addElement(P(text=str(hours)))
    row.addElement(hours_cell)
    
    # % of Hours cell (empty - agent fills formula)
    pct_cell = TableCell()
    row.addElement(pct_cell)
    
    # Tip Share cell (empty - agent fills formula)
    share_cell = TableCell()
    row.addElement(share_cell)
    
    table.addElement(row)

# Row 7: Empty row
empty_row = TableRow()
for _ in range(4):
    empty_row.addElement(TableCell())
table.addElement(empty_row)

# Row 8: TOTALS row
totals_row = TableRow()
# Cell A8: "TOTALS" label
label_cell = TableCell(valuetype="string")
label_cell.addElement(P(text="TOTALS"))
totals_row.addElement(label_cell)

# Cell B8: Empty (agent fills SUM formula for total hours)
totals_row.addElement(TableCell())

# Cell C8: Empty (optional verification)
totals_row.addElement(TableCell())

# Cell D8: Empty (optional verification)
totals_row.addElement(TableCell())

table.addElement(totals_row)

# Rows 9-10: Empty rows for spacing
for _ in range(2):
    empty_row = TableRow()
    for _ in range(4):
        empty_row.addElement(TableCell())
    table.addElement(empty_row)

# Row 11: "Tip Sources" header
tip_header_row = TableRow()
tip_header_cell = TableCell(valuetype="string")
tip_header_cell.addElement(P(text="Tip Sources"))
tip_header_row.addElement(tip_header_cell)
for _ in range(3):
    tip_header_row.addElement(TableCell())
table.addElement(tip_header_row)

# Row 12: Cash Tips
cash_row = TableRow()
cash_label = TableCell(valuetype="string")
cash_label.addElement(P(text="Cash Tips:"))
cash_row.addElement(cash_label)
cash_value = TableCell(valuetype="float", value="287.50")
cash_value.addElement(P(text="$287.50"))
cash_row.addElement(cash_value)
for _ in range(2):
    cash_row.addElement(TableCell())
table.addElement(cash_row)

# Row 13: Credit Card Tips
credit_row = TableRow()
credit_label = TableCell(valuetype="string")
credit_label.addElement(P(text="Credit Card Tips:"))
credit_row.addElement(credit_label)
credit_value = TableCell(valuetype="float", value="312.00")
credit_value.addElement(P(text="$312.00"))
credit_row.addElement(credit_value)
for _ in range(2):
    credit_row.addElement(TableCell())
table.addElement(credit_row)

# Row 14: Total Tips (empty - agent fills formula)
total_row = TableRow()
total_label = TableCell(valuetype="string")
total_label.addElement(P(text="Total Tips:"))
total_row.addElement(total_label)
total_value = TableCell()  # Empty cell for agent to fill
total_row.addElement(total_value)
for _ in range(2):
    total_row.addElement(TableCell())
table.addElement(total_row)

# Add some extra empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(4):
        row.addElement(TableCell())
    table.addElement(row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/tip_pool.ods")
print("✅ Created tip_pool.ods with pre-filled data")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/tip_pool.ods
sudo chmod 666 /home/ga/Documents/tip_pool.ods

# Verify file was created
if [ -f "/home/ga/Documents/tip_pool.ods" ]; then
    echo "✅ File created successfully"
    ls -lh /home/ga/Documents/tip_pool.ods
else
    echo "❌ ERROR: File creation failed"
    exit 1
fi

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/tip_pool.ods > /tmp/calc_tip_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_tip_task.log
    # exit 1
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # exit 1
fi

# Click on center of the screen to select current desktop (should be done in all tasks)
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

# Position cursor at B13 (Total Tips cell) to guide the agent
echo "Positioning cursor at Total Tips cell..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to B13 (Ctrl+G could be used but direct navigation is simpler)
safe_xdotool ga :1 key ctrl+g
sleep 0.5
safe_xdotool ga :1 type "B13"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Tip Pool Calculator Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "========================================"
echo "🎯 Goal: Calculate fair tip distribution based on hours worked"
echo ""
echo "📝 Required Formulas:"
echo "  1. Cell B13 (Total Tips): =SUM(B11:B12)"
echo "  2. Cell B8 (Total Hours): =SUM(B2:B6)"
echo "  3. Cell C2 (Alice's %): =B2/\$B\$8 (then copy to C3:C6)"
echo "  4. Cell D2 (Alice's Share): =C2*\$B\$13 (then copy to D3:D6)"
echo ""
echo "💡 Tips:"
echo "  - Use \$ for absolute references (\$B\$8, \$B\$13)"
echo "  - Copy formulas with Ctrl+C, Ctrl+V"
echo "  - Verify: Total distributed = Total collected"
echo "========================================"