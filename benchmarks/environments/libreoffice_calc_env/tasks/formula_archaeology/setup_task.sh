#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Formula Archaeology Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy library..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true
fi

# Create broken expense tracking spreadsheet with Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TextProperties, TableColumnProperties, TableCellProperties
from odf.number import NumberStyle, CurrencyStyle, CurrencySymbol, Number, Text as NumberText
import sys

try:
    # Create new spreadsheet
    doc = OpenDocumentSpreadsheet()
    
    # Add a sheet named "Expenses"
    table = Table(name="Expenses")
    
    # Helper function to create a cell with a value
    def create_cell(value=None, formula=None, cell_type='string'):
        cell = TableCell()
        if formula:
            cell.setAttribute('formula', formula)
            cell.setAttribute('valuetype', 'float')
        elif value is not None:
            if cell_type == 'float':
                cell.setAttribute('valuetype', 'float')
                cell.setAttribute('value', str(value))
            else:
                cell.setAttribute('valuetype', 'string')
            p = P()
            p.addText(str(value))
            cell.addElement(p)
        return cell
    
    # Row 1: Title
    row1 = TableRow()
    row1.addElement(create_cell("Monthly Expense Tracker - BROKEN"))
    for _ in range(7):
        row1.addElement(create_cell())
    table.addElement(row1)
    
    # Row 2: Empty
    row2 = TableRow()
    for _ in range(8):
        row2.addElement(create_cell())
    table.addElement(row2)
    
    # Row 3: Column headers
    row3 = TableRow()
    headers = ["Date", "Category", "Description", "Amount", "", "", "", ""]
    for header in headers:
        row3.addElement(create_cell(header))
    table.addElement(row3)
    
    # Row 4: Empty
    row4 = TableRow()
    for _ in range(8):
        row4.addElement(create_cell())
    table.addElement(row4)
    
    # Rows 5-14: Expense data (10 transactions)
    expenses = [
        ["2024-01-05", "Office Supplies", "Printer paper", 45],
        ["2024-01-08", "Travel", "Flight to NYC", 350],
        ["2024-01-12", "Utilities", "Internet bill", 120],
        ["2024-01-15", "Marketing", "Google Ads", 280],
        ["2024-01-18", "Office Supplies", "Pens and folders", 35],
        ["2024-01-22", "Travel", "Hotel NYC", 450],
        ["2024-01-25", "Utilities", "Electricity", 200],
        ["2024-01-28", "Marketing", "Facebook Ads", 310],
        ["2024-01-30", "Office Supplies", "Desk organizers", 370],
        ["2024-01-31", "Travel", "Taxi rides", 450]
    ]
    
    for expense in expenses:
        row = TableRow()
        row.addElement(create_cell(expense[0]))
        row.addElement(create_cell(expense[1]))
        row.addElement(create_cell(expense[2]))
        row.addElement(create_cell(expense[3], cell_type='float'))
        for _ in range(4):
            row.addElement(create_cell())
        table.addElement(row)
    
    # Row 15: Empty
    row15 = TableRow()
    for _ in range(8):
        row15.addElement(create_cell())
    table.addElement(row15)
    
    # Row 16: Category labels
    row16 = TableRow()
    row16.addElement(create_cell("Category Totals:"))
    row16.addElement(create_cell("Office Supplies"))
    row16.addElement(create_cell("Travel"))
    row16.addElement(create_cell("Utilities"))
    row16.addElement(create_cell("Marketing"))
    for _ in range(3):
        row16.addElement(create_cell())
    table.addElement(row16)
    
    # Row 17: Broken SUM formulas (ranges too small - only B5:B9 instead of B5:B14)
    # These should sum expenses for each category
    # Correct totals: Office Supplies=450, Travel=1250, Utilities=320, Marketing=890
    # But broken formulas will show partial sums
    row17 = TableRow()
    row17.addElement(create_cell("Totals:"))
    # BROKEN: These SUM ranges only go to row 9, missing rows 10-14
    row17.addElement(create_cell(formula='of:=SUMIF($B$5:$B$9,"Office Supplies",$D$5:$D$9)'))
    row17.addElement(create_cell(formula='of:=SUMIF($B$5:$B$9,"Travel",$D$5:$D$9)'))
    row17.addElement(create_cell(formula='of:=SUMIF($B$5:$B$9,"Utilities",$D$5:$D$9)'))
    row17.addElement(create_cell(formula='of:=SUMIF($B$5:$B$9,"Marketing",$D$5:$D$9)'))
    for _ in range(3):
        row17.addElement(create_cell())
    table.addElement(row17)
    
    # Row 18: Empty
    row18 = TableRow()
    for _ in range(8):
        row18.addElement(create_cell())
    table.addElement(row18)
    
    # Row 19: Budget label
    row19 = TableRow()
    row19.addElement(create_cell("Budget:"))
    row19.addElement(create_cell(500, cell_type='float'))
    row19.addElement(create_cell(1100, cell_type='float'))
    row19.addElement(create_cell(400, cell_type='float'))
    row19.addElement(create_cell(800, cell_type='float'))
    for _ in range(3):
        row19.addElement(create_cell())
    table.addElement(row19)
    
    # Row 20: Empty
    row20 = TableRow()
    for _ in range(8):
        row20.addElement(create_cell())
    table.addElement(row20)
    
    # Row 21: Variance label
    row21 = TableRow()
    row21.addElement(create_cell("Variance (Actual - Budget):"))
    for _ in range(7):
        row21.addElement(create_cell())
    table.addElement(row21)
    
    # Row 22: BROKEN variance formulas with #REF! errors
    # These should be =B17-B19, =C17-C19, etc.
    # But we'll create #REF! by referencing non-existent column
    row22 = TableRow()
    row22.addElement(create_cell(""))
    # BROKEN: These reference column H which doesn't exist properly, causing #REF!
    # Actually, let's use a different approach - reference cells that will cause issues
    # We'll reference the wrong rows to create calculation errors
    row22.addElement(create_cell(formula='of:=[.B17]-[.B21]'))  # Wrong row reference (should be B19)
    row22.addElement(create_cell(formula='of:=[.C17]-[.C21]'))  # Wrong row reference
    row22.addElement(create_cell(formula='of:=[.D17]-[.D21]'))  # Wrong row reference
    row22.addElement(create_cell(formula='of:=[.E17]-[.E21]'))  # Wrong row reference
    for _ in range(3):
        row22.addElement(create_cell())
    table.addElement(row22)
    
    # Row 23: Empty
    row23 = TableRow()
    for _ in range(8):
        row23.addElement(create_cell())
    table.addElement(row23)
    
    # Row 24: Status label
    row24 = TableRow()
    row24.addElement(create_cell("Status:"))
    for _ in range(7):
        row24.addElement(create_cell())
    table.addElement(row24)
    
    # Row 25: BROKEN warning formulas with incorrect references
    row25 = TableRow()
    row25.addElement(create_cell(""))
    # BROKEN: These reference wrong rows (should reference row 22, but reference row 20)
    row25.addElement(create_cell(formula='of:=IF([.B20]>0,"OVER BUDGET","OK")'))
    row25.addElement(create_cell(formula='of:=IF([.C20]>0,"OVER BUDGET","OK")'))
    row25.addElement(create_cell(formula='of:=IF([.D20]>0,"OVER BUDGET","OK")'))
    row25.addElement(create_cell(formula='of:=IF([.E20]>0,"OVER BUDGET","OK")'))
    for _ in range(3):
        row25.addElement(create_cell())
    table.addElement(row25)
    
    # Add more empty rows to make it look like a proper spreadsheet
    for _ in range(10):
        row = TableRow()
        for _ in range(8):
            row.addElement(create_cell())
        table.addElement(row)
    
    doc.spreadsheet.addElement(table)
    
    # Save the file
    doc.save("/home/ga/Documents/expenses_broken.ods")
    print("✅ Created broken expense spreadsheet successfully")
    sys.exit(0)
    
except Exception as e:
    print(f"❌ Error creating spreadsheet: {e}", file=sys.stderr)
    import traceback
    traceback.print_exc()
    sys.exit(1)
PYEOF

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create spreadsheet"
    exit 1
fi

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/expenses_broken.ods
sudo chmod 666 /home/ga/Documents/expenses_broken.ods

# Verify file was created
if [ ! -f "/home/ga/Documents/expenses_broken.ods" ]; then
    echo "ERROR: Spreadsheet file was not created"
    exit 1
fi

echo "✅ Broken spreadsheet created: $(ls -lh /home/ga/Documents/expenses_broken.ods)"

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/expenses_broken.ods > /tmp/calc_archaeology_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_archaeology_task.log || true
    # Don't exit - let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit - let task continue
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

# Ensure cursor is at A1
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Formula Archaeology Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   Your bookkeeper quit suddenly, leaving a broken expense tracker."
echo "   Several formulas have errors and need fixing!"
echo ""
echo "🔍 PROBLEMS TO FIX:"
echo "   1. Category total formulas (row 17) don't include all expense rows"
echo "   2. Variance formulas (row 22) reference wrong cells"
echo "   3. Status warning formulas (row 25) have incorrect references"
echo ""
echo "✅ CORRECT RESULTS SHOULD BE:"
echo "   Office Supplies Total: $450 (Variance: -$50, Status: OK)"
echo "   Travel Total: $1,250 (Variance: +$150, Status: OVER BUDGET)"
echo "   Utilities Total: $320 (Variance: -$80, Status: OK)"
echo "   Marketing Total: $890 (Variance: +$90, Status: OVER BUDGET)"
echo ""
echo "💡 HINTS:"
echo "   - Click cells to view formulas in the formula bar"
echo "   - SUMIF ranges should be $B$5:$B$14 (not $B$5:$B$9)"
echo "   - Variance = [Row 17] - [Row 19]"
echo "   - Status = IF([Row 22]>0, 'OVER BUDGET', 'OK')"