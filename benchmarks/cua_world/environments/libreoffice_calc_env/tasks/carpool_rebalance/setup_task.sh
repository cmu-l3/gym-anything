#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Carpool Rebalance Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not present (for ODS creation)
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf
fi

# Create the initial broken carpool spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
import random

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Helper to create cell with value
def create_cell(value=None, formula=None, value_type=None):
    cell = TableCell()
    if formula:
        cell.setAttribute('formula', formula)
        cell.setAttribute('valuetype', 'float')
    elif value is not None:
        if isinstance(value, (int, float)):
            cell.setAttribute('valuetype', 'float')
            cell.setAttribute('value', str(value))
        else:
            cell.setAttribute('valuetype', 'string')
        p = P(text=str(value))
        cell.addElement(p)
    return cell

# Sheet 1: Drive Log
drive_log = Table(name="Drive Log")

# Drive log header
header_row = TableRow()
for header in ["Date", "Driver", "Passengers", "Miles"]:
    cell = create_cell(header)
    header_row.addElement(cell)
drive_log.addElement(header_row)

# Drive log data - Garcia: 7 times, Kim: 3 times, others: 3-4 times
drive_data = [
    ["2024-01-08", "Garcia", "3", "8.4"],
    ["2024-01-09", "Lee", "4", "11.6"],
    ["2024-01-10", "Martinez", "2", "8.4"],  # Old mileage will be used
    ["2024-01-11", "Thompson", "3", "13.0"],
    ["2024-01-12", "Kim", "4", "10.0"],
    ["2024-01-15", "Garcia", "3", "8.4"],
    ["2024-01-16", "Lee", "2", "11.6"],
    ["2024-01-17", "Garcia", "4", "8.4"],
    ["2024-01-18", "Martinez", "3", "8.4"],
    ["2024-01-19", "Thompson", "2", "13.0"],
    ["2024-01-22", "Garcia", "3", "8.4"],
    ["2024-01-23", "Kim", "4", "10.0"],
    ["2024-01-24", "Garcia", "2", "8.4"],
    ["2024-01-25", "Lee", "3", "11.6"],
    ["2024-01-26", "Thompson", "4", "13.0"],
    ["2024-01-29", "Garcia", "3", "8.4"],
    ["2024-01-30", "Martinez", "2", "8.4"],
    ["2024-01-31", "Kim", "4", "10.0"],
    ["2024-02-01", "Garcia", "3", "8.4"],
    ["2024-02-02", "Lee", "2", "11.6"],
]

for row_data in drive_data:
    row = TableRow()
    for val in row_data:
        cell = create_cell(val)
        row.addElement(cell)
    drive_log.addElement(row)

doc.spreadsheet.addElement(drive_log)

# Sheet 2: Family Info
family_info = Table(name="Family Info")

# Header
header_row = TableRow()
for header in ["Family Name", "Address", "Miles to School (one-way)"]:
    cell = create_cell(header)
    header_row.addElement(cell)
family_info.addElement(header_row)

# Family data - Martinez has OLD mileage (should be 5.8)
family_data = [
    ["Garcia", "123 Oak Street", 4.2],
    ["Kim", "456 Maple Avenue", 5.0],
    ["Lee", "789 Pine Road", 5.8],
    ["Martinez", "321 Elm Drive", 4.2],  # OLD - needs update to 5.8
    ["Thompson", "654 Birch Lane", 6.5],
]

for row_data in family_data:
    row = TableRow()
    for val in row_data:
        cell = create_cell(val)
        row.addElement(cell)
    family_info.addElement(row)

doc.spreadsheet.addElement(family_info)

# Sheet 3: Cost Summary (with broken formulas)
cost_summary = Table(name="Cost Summary")

# Add instruction comment in A1
instruction_row = TableRow()
instr_cell = create_cell("PROBLEMS TO FIX: (1) Garcia drove 7 times, Kim only 3 times - imbalanced! (2) Martinez moved - update mileage to 5.8 miles (3) Cost formulas broken - fix #REF errors")
instruction_row.addElement(instr_cell)
for _ in range(6):  # Merge across columns
    instruction_row.addElement(create_cell())
cost_summary.addElement(instruction_row)

# Assumptions row
assumption_row = TableRow()
assumption_row.addElement(create_cell("Gas Price ($/gal):"))
assumption_row.addElement(create_cell(3.85))
assumption_row.addElement(create_cell("Vehicle MPG:"))
assumption_row.addElement(create_cell(28))
cost_summary.addElement(assumption_row)

# Empty row
empty_row = TableRow()
for _ in range(7):
    empty_row.addElement(create_cell())
cost_summary.addElement(empty_row)

# Header row
header_row = TableRow()
for header in ["Family Name", "Drive Count", "Total Miles", "Gas Cost ($)", "Fair Share ($)", "Balance ($)"]:
    cell = create_cell(header)
    header_row.addElement(cell)
cost_summary.addElement(header_row)

# Family rows with formulas (some broken)
families = ["Garcia", "Kim", "Lee", "Martinez", "Thompson"]

for i, family in enumerate(families):
    row = TableRow()
    row_num = i + 5  # Starting at row 5 (after headers)
    
    # Family name
    row.addElement(create_cell(family))
    
    # Drive count - COUNTIF formula (working)
    formula = f"of:=COUNTIF([.Drive Log.$B:$B],A{row_num})"
    row.addElement(create_cell(formula=formula))
    
    # Total miles - BROKEN FORMULA (wrong reference or #REF)
    # Should be: =B{row_num}*VLOOKUP(A{row_num},[.Family Info.$A:$C],3,0)*2
    # But we'll make it broken with wrong column reference
    if family == "Martinez":
        # This one has a #REF error
        broken_formula = f"of:=B{row_num}*VLOOKUP(A{row_num},[.Family Info.$A:$D],5,0)*2"
    else:
        # These reference the wrong column (column 2 instead of 3)
        broken_formula = f"of:=B{row_num}*VLOOKUP(A{row_num},[.Family Info.$A:$C],2,0)*2"
    row.addElement(create_cell(formula=broken_formula))
    
    # Gas cost - depends on total miles (will be wrong because previous formula is wrong)
    formula = f"of:=C{row_num}*($B$2/$D$2)"
    row.addElement(create_cell(formula=formula))
    
    # Fair share - empty for now, should be filled
    row.addElement(create_cell())
    
    # Balance - empty for now, should be filled
    row.addElement(create_cell())
    
    cost_summary.addElement(row)

# Add a row for totals/verification
total_row = TableRow()
total_row.addElement(create_cell("TOTAL"))
total_row.addElement(create_cell(formula="of:=SUM(B5:B9)"))
total_row.addElement(create_cell(formula="of:=SUM(C5:C9)"))
total_row.addElement(create_cell(formula="of:=SUM(D5:D9)"))
total_row.addElement(create_cell())
total_row.addElement(create_cell(formula="of:=SUM(F5:F9)"))
cost_summary.addElement(total_row)

doc.spreadsheet.addElement(cost_summary)

# Save the file
output_path = "/home/ga/Documents/carpool_schedule.ods"
doc.save(output_path)
print(f"Created broken carpool spreadsheet: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/carpool_schedule.ods
sudo chmod 666 /home/ga/Documents/carpool_schedule.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/carpool_schedule.ods > /tmp/calc_carpool_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_carpool_task.log || true
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

# Navigate to Cost Summary sheet (should be the active sheet)
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.3
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.3

# Position cursor at a useful location (cell A4 - header row)
safe_xdotool ga :1 key ctrl+Home
sleep 0.2
safe_xdotool ga :1 key Down Down Down
sleep 0.2

echo "=== Carpool Rebalance Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Check Drive Log sheet - Garcia drove 7 times, Kim only 3 times"
echo "  2. Go to Family Info sheet - update Martinez mileage from 4.2 to 5.8"
echo "  3. Go to Cost Summary sheet - fix broken formulas in column C (Total Miles)"
echo "  4. Calculate Fair Share amount in column E: =D10/5 (total cost ÷ 5 families)"
echo "  5. Calculate Balance in column F: =D5-\$E\$5 (actual cost - fair share)"
echo "  6. Verify sum of balances (F10) equals \$0.00"
echo ""
echo "💡 Hints:"
echo "  - Total Miles formula: =B5*VLOOKUP(A5,'Family Info'.\$A:\$C,3,0)*2"
echo "  - Fair Share: Total gas cost ÷ 5 families"
echo "  - Balance: Actual cost - Fair share (positive = owed, negative = owes)"