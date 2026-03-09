#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Shared Expense Reconciliation Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install odfpy if not already installed
if ! python3 -c "import odf" 2>/dev/null; then
    echo "Installing odfpy..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1
fi

# Create pre-populated ODS file using Python
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell
from odf.text import P
from odf.style import Style, TableColumnProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Expense Reconciliation"
table = Table(name="Expense Reconciliation")
doc.spreadsheet.addElement(table)

# Helper function to create cell with value
def create_cell(value, value_type='string'):
    cell = TableCell()
    if value_type == 'string':
        cell.setAttrNS('urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'value-type', 'string')
        p = P(text=str(value))
        cell.addElement(p)
    elif value_type == 'float':
        cell.setAttrNS('urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'value-type', 'float')
        cell.setAttrNS('urn:oasis:names:tc:opendocument:xmlns:office:1.0', 'value', str(value))
        p = P(text=str(value))
        cell.addElement(p)
    return cell

# Header row
header_row = TableRow()
for header in ["Date", "Description", "Amount", "Paid By", "Split Type"]:
    header_row.addElement(create_cell(header, 'string'))
table.addElement(header_row)

# Expense data - carefully crafted to create realistic balances
expenses = [
    ("2024-01-05", "Groceries", 87.50, "Alice", "Equal"),
    ("2024-01-07", "Internet Bill", 60.00, "Bob", "Equal"),
    ("2024-01-10", "Cleaning Supplies", 34.20, "Carol", "Equal"),
    ("2024-01-12", "Alice's Dry Cleaning", 25.00, "Alice", "Alice"),
    ("2024-01-15", "Rent", 1500.00, "Alice", "Equal"),
    ("2024-01-18", "Bob's Medication", 45.00, "Carol", "Bob"),
    ("2024-01-22", "Groceries", 102.30, "Bob", "Equal"),
    ("2024-01-25", "Electricity", 78.00, "Carol", "Equal"),
    ("2024-01-28", "Carol's Books", 56.00, "Bob", "Carol"),
    ("2024-01-30", "Groceries", 94.75, "Alice", "Equal"),
]

for expense in expenses:
    row = TableRow()
    row.addElement(create_cell(expense[0], 'string'))  # Date
    row.addElement(create_cell(expense[1], 'string'))  # Description
    row.addElement(create_cell(expense[2], 'float'))   # Amount
    row.addElement(create_cell(expense[3], 'string'))  # Paid By
    row.addElement(create_cell(expense[4], 'string'))  # Split Type
    table.addElement(row)

# Add blank row
blank_row = TableRow()
for _ in range(5):
    blank_row.addElement(create_cell("", 'string'))
table.addElement(blank_row)

# Summary section header (row 12)
summary_header_row = TableRow()
summary_header_row.addElement(create_cell("SUMMARY SECTION - TO BE COMPLETED:", 'string'))
for _ in range(4):
    summary_header_row.addElement(create_cell("", 'string'))
table.addElement(summary_header_row)

# Summary table headers (row 13)
summary_table_header = TableRow()
for header in ["Person", "Total Paid", "Total Owed", "Net Balance"]:
    summary_table_header.addElement(create_cell(header, 'string'))
table.addElement(summary_table_header)

# Summary data rows (rows 14-16) - Alice, Bob, Carol
for person in ["Alice", "Bob", "Carol"]:
    row = TableRow()
    row.addElement(create_cell(person, 'string'))
    # Empty cells for formulas to be added
    row.addElement(create_cell("", 'string'))
    row.addElement(create_cell("", 'string'))
    row.addElement(create_cell("", 'string'))
    table.addElement(row)

# Check row (row 17)
check_row = TableRow()
check_row.addElement(create_cell("", 'string'))
check_row.addElement(create_cell("", 'string'))
check_row.addElement(create_cell("CHECK (should be 0):", 'string'))
check_row.addElement(create_cell("", 'string'))
table.addElement(check_row)

# Add blank row
blank_row2 = TableRow()
for _ in range(5):
    blank_row2.addElement(create_cell("", 'string'))
table.addElement(blank_row2)

# Settlement instructions header (row 19)
settlement_header = TableRow()
settlement_header.addElement(create_cell("SETTLEMENT INSTRUCTIONS:", 'string'))
for _ in range(4):
    settlement_header.addElement(create_cell("", 'string'))
table.addElement(settlement_header)

# Empty rows for settlement instructions (rows 20-22)
for _ in range(3):
    row = TableRow()
    for _ in range(5):
        row.addElement(create_cell("", 'string'))
    table.addElement(row)

# Add more empty rows to make it a proper spreadsheet
for _ in range(10):
    row = TableRow()
    for _ in range(10):
        cell = TableCell()
        row.addElement(cell)
    table.addElement(row)

# Save the file
output_path = "/home/ga/Documents/expense_reconciliation.ods"
doc.save(output_path)
print(f"✅ Created expense reconciliation template: {output_path}")
PYEOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/expense_reconciliation.ods
sudo chmod 666 /home/ga/Documents/expense_reconciliation.ods

# Launch LibreOffice Calc with the spreadsheet
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/expense_reconciliation.ods > /tmp/calc_expense_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_expense_task.log || true
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

# Move cursor to the summary section (cell B14 - first formula cell)
echo "Positioning cursor at summary section..."
safe_xdotool ga :1 key ctrl+Home
sleep 0.3
# Move to B14 (Total Paid for Alice)
safe_xdotool ga :1 key ctrl+g  # Go To dialog
sleep 0.5
safe_xdotool ga :1 type "B14"
sleep 0.3
safe_xdotool ga :1 key Return
sleep 0.3

echo "=== Shared Expense Reconciliation Task Setup Complete ==="
echo ""
echo "📊 EXPENSE LOG:"
echo "  - 10 expenses from January 2024"
echo "  - 3 roommates: Alice, Bob, Carol"
echo "  - Mixed split types: Equal and Assigned"
echo ""
echo "📝 YOUR TASK:"
echo "  1. Calculate Total Paid (B14:B16) - How much each person paid"
echo "     Hint: Use SUMIF(D:D,\"Alice\",C:C) for Alice's total"
echo ""
echo "  2. Calculate Total Owed (C14:C16) - Each person's fair share"
echo "     - For 'Equal' split expenses: divide by 3"
echo "     - For assigned expenses: full amount to that person"
echo ""
echo "  3. Calculate Net Balance (D14:D16) - Paid minus Owed"
echo "     Formula: =B14-C14"
echo ""
echo "  4. Verify Zero-Sum (D17) - Sum of all balances should be 0"
echo "     Formula: =SUM(D14:D16)"
echo ""
echo "  5. Apply conditional formatting to balances (D14:D16)"
echo "     - Negative values (debts) in RED"
echo "     - Positive values (credits) in GREEN"
echo ""
echo "  6. Write settlement instructions (rows 20-22)"
echo "     Example: 'Bob pays Alice $XX.XX'"
echo ""
echo "💡 TIPS:"
echo "  - Cursor is positioned at B14 (first formula cell)"
echo "  - All balances must sum to zero (accounting principle)"
echo "  - Use SUMIF for conditional summing"
echo "  - Negative balance = person owes money"
echo "  - Positive balance = person is owed money"