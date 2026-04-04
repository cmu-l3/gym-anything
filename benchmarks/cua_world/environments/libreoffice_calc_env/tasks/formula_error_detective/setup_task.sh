#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Formula Error Detective Task ==="

# Ensure python3-odf is installed for ODS file creation
if ! python3 -c "from odf import opendocument" 2>/dev/null; then
    echo "Installing python3-odf..."
# sudo apt-get update -qq && sudo apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Create the broken spreadsheet using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Create Expenses sheet (intentionally named differently to cause #NAME? errors later)
expenses_table = Table(name="Monthly_Expenses")
doc.spreadsheet.addElement(expenses_table)

# Add header row
header_row = TableRow()
for header in ["Date", "Category", "Amount", "Notes"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
expenses_table.addElement(header_row)

# Add expense data (realistic monthly expenses)
expense_data = [
    ["2024-01-05", "Office Supplies", 450, "Printer paper and toner"],
    ["2024-01-12", "Travel", 1200, "Client meeting in Boston"],
    ["2024-01-18", "Software", 299, "Adobe subscription"],
    ["2024-01-22", "Office Supplies", 85, "Notebooks and pens"],
    ["2024-01-28", "Utilities", 380, "Office electricity"],
    ["2024-02-03", "Travel", 890, "Conference in Chicago"],
    ["2024-02-10", "Software", 149, "Slack premium"],
    ["2024-02-15", "Office Supplies", 215, "Desk organizers"],
    ["2024-02-20", "Marketing", 2500, "Social media ads"],
    ["2024-02-25", "Utilities", 420, "Internet and phone"],
    ["2024-03-01", "Travel", 1650, "Sales trip to LA"],
    ["2024-03-08", "Software", 99, "Zoom subscription"],
    ["2024-03-12", "Office Supplies", 320, "Coffee and snacks"],
    ["2024-03-19", "Marketing", 1800, "Print materials"],
    ["2024-03-25", "Utilities", 395, "Office utilities"],
]

for data_row in expense_data:
    row = TableRow()
    # Date (as string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(data_row[0])))
    row.addElement(cell)
    # Category (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(data_row[1])))
    row.addElement(cell)
    # Amount (float) - THIS IS COLUMN C (index 2, will be referenced)
    cell = TableCell(valuetype="float", value=str(data_row[2]))
    cell.addElement(P(text=str(data_row[2])))
    row.addElement(cell)
    # Notes (string)
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=str(data_row[3])))
    row.addElement(cell)
    expenses_table.addElement(row)

# Add empty rows to pad out the sheet
for _ in range(35):
    row = TableRow()
    for _ in range(6):
        cell = TableCell()
        row.addElement(cell)
    expenses_table.addElement(row)

# Create Summary sheet with BROKEN formulas
summary_table = Table(name="Summary")
doc.spreadsheet.addElement(summary_table)

# Header row
header_row = TableRow()
for header in ["Category", "Total"]:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    header_row.addElement(cell)
summary_table.addElement(header_row)

# Category summary rows with BROKEN formulas
# These formulas will have errors because:
# 1. They reference "Expenses" sheet but it's named "Monthly_Expenses" → #NAME? error
# 2. Some reference wrong columns → #REF! error
# 3. One includes header row causing #VALUE! error

broken_categories = [
    ("Office Supplies", '=SUMIF(Expenses.B:B,"Office Supplies",Expenses.C:C)'),  # #NAME? - sheet name wrong
    ("Travel", '=SUMIF(Expenses.B:B,"Travel",Expenses.D:D)'),  # #NAME? + wrong column
    ("Software", '=SUMIF(Expenses.B:B,"Software",Expenses.C:C)'),  # #NAME?
    ("Marketing", '=SUMIF(Expenses.B2:B20,"Marketing",Expenses.C1:C20)'),  # #NAME? + includes header
    ("Utilities", '=SUMIF(Expenses.B:B,"Utilities",Expenses.C:C)'),  # #NAME?
]

for category, formula in broken_categories:
    row = TableRow()
    # Category name
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=category))
    row.addElement(cell)
    # Broken formula
    cell = TableCell(valuetype="float", formula=formula)
    cell.addElement(P(text="#NAME?"))  # Display error
    row.addElement(cell)
    summary_table.addElement(row)

# Add empty row
row = TableRow()
for _ in range(3):
    cell = TableCell()
    row.addElement(cell)
summary_table.addElement(row)

# Total row with broken formula
row = TableRow()
cell = TableCell(valuetype="string")
cell.addElement(P(text="TOTAL EXPENSES"))
row.addElement(cell)
# This formula has #REF! error
cell = TableCell(valuetype="float", formula='=SUM(B2:B6)')
cell.addElement(P(text="#REF!"))
row.addElement(cell)
summary_table.addElement(row)

# Add padding rows
for _ in range(15):
    row = TableRow()
    for _ in range(4):
        cell = TableCell()
        row.addElement(cell)
    summary_table.addElement(row)

# Save the file
doc.save("/home/ga/Documents/expense_tracker_broken.ods")
print("✅ Created broken spreadsheet with #NAME?, #REF!, and #VALUE! errors")

# Print expected corrections for verification
print("\n=== Expected Formula Corrections ===")
print("Office Supplies: =SUMIF(Monthly_Expenses.B:B,\"Office Supplies\",Monthly_Expenses.C:C) → should equal 1070")
print("Travel: =SUMIF(Monthly_Expenses.B:B,\"Travel\",Monthly_Expenses.C:C) → should equal 3740")
print("Software: =SUMIF(Monthly_Expenses.B:B,\"Software\",Monthly_Expenses.C:C) → should equal 547")
print("Marketing: =SUMIF(Monthly_Expenses.B:B,\"Marketing\",Monthly_Expenses.C:C) → should equal 4300")
print("Utilities: =SUMIF(Monthly_Expenses.B:B,\"Utilities\",Monthly_Expenses.C:C) → should equal 1195")
print("TOTAL: =SUM(B2:B6) → should equal 10852")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/expense_tracker_broken.ods
sudo chmod 666 /home/ga/Documents/expense_tracker_broken.ods

# Verify file was created
if [ ! -f "/home/ga/Documents/expense_tracker_broken.ods" ]; then
    echo "ERROR: Failed to create broken spreadsheet"
    exit 1
fi

echo "✅ Broken spreadsheet created: expense_tracker_broken.ods"
ls -lh /home/ga/Documents/expense_tracker_broken.ods

# Launch LibreOffice Calc with the broken spreadsheet
echo "Launching LibreOffice Calc with broken spreadsheet..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/expense_tracker_broken.ods > /tmp/calc_error_detective.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_error_detective.log || true
    # Don't exit, let task continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, let task continue
fi

# Click on center of screen to select current desktop (should be done in all tasks)
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

# Navigate to Summary sheet to show errors prominently
echo "Navigating to Summary sheet..."
safe_xdotool ga :1 key ctrl+Page_Down
sleep 0.5

# Position cursor at first broken formula
safe_xdotool ga :1 key ctrl+Home
sleep 0.3

echo "=== Formula Error Detective Task Setup Complete ==="
echo "📋 Task Summary:"
echo "  - Spreadsheet has #NAME?, #REF!, and #VALUE! errors"
echo "  - Sheets: 'Monthly_Expenses' (data) and 'Summary' (broken formulas)"
echo "  - Your job: Fix all formula errors so calculations work correctly"
echo ""
echo "💡 Hints:"
echo "  - Check sheet names (tabs at bottom)"
echo "  - Inspect formulas by clicking cells and looking at formula bar"
echo "  - Fix #NAME? errors by correcting sheet references"
echo "  - Fix #REF! errors by updating cell ranges"
echo "  - Verify totals make sense after repairs"
echo ""
echo "🎯 Goal: Zero error codes, working formulas, accurate calculations"