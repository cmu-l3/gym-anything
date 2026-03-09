#!/bin/bash
# set -euo pipefail

# Source shared utilities
source /workspace/scripts/task_utils.sh

echo "=== Setting up Bank Import Formatter Task ==="

# Create task directory
sudo -u ga mkdir -p /home/ga/Documents

# Install required Python libraries for ODS creation
echo "Installing Python ODF library..."
# apt-get update -qq && apt-get install -y -qq python3-odf > /dev/null 2>&1 || true

# Create messy bank export ODS file with realistic messy structure
echo "Creating messy bank export file..."
python3 << 'PYEOF'
from odf.opendocument import OpenDocumentSpreadsheet
from odf.table import Table, TableRow, TableCell, TableColumn
from odf.text import P
from odf.style import Style, TableColumnProperties, ParagraphProperties, TextProperties
from odf.number import NumberStyle, Number, Text as NumberText, CurrencySymbol
import datetime

# Create new spreadsheet
doc = OpenDocumentSpreadsheet()

# Add a sheet named "Transactions"
table = Table(name="Transactions")

# Row 1: Merged header with bank name (simulated by spanning columns)
row1 = TableRow()
cell = TableCell()
cell.addElement(P(text="FIRST NATIONAL BANK - TRANSACTION EXPORT"))
cell.setAttribute('numbercolumnsspanned', '7')
row1.addElement(cell)
for _ in range(6):  # Add empty cells for merge
    row1.addElement(TableCell())
table.addElement(row1)

# Row 2: Export timestamp
row2 = TableRow()
cell = TableCell()
cell.addElement(P(text="Export Date: 2024-01-31 14:23:15"))
cell.setAttribute('numbercolumnsspanned', '7')
row2.addElement(cell)
for _ in range(6):
    row2.addElement(TableCell())
table.addElement(row2)

# Row 3: Column headers (non-standard names)
row3 = TableRow()
headers = ["Transaction Date", "Memo/Description", "Debit", "Credit", "Balance", "Account Number", "Check Number"]
for header in headers:
    cell = TableCell(valuetype="string")
    cell.addElement(P(text=header))
    row3.addElement(cell)
table.addElement(row3)

# Sample transaction data (15 transactions)
transactions = [
    ("01/15/2024", "Starbucks Coffee", "4.50", "", "2495.50", "****1234", ""),
    ("01/15/2024", "Paycheck Deposit", "", "2500.00", "4995.50", "****1234", ""),
    ("01/16/2024", "Grocery Store", "87.23", "", "4908.27", "****1234", ""),
    ("01/17/2024", "Gas Station", "45.00", "", "4863.27", "****1234", ""),
    ("01/18/2024", "Restaurant, Fine Dining", "125.50", "", "4737.77", "****1234", ""),
    ("01/19/2024", "Online Purchase", "32.99", "", "4704.78", "****1234", ""),
    ("01/20/2024", "Electric Bill", "156.80", "", "4547.98", "****1234", ""),
    ("01/22/2024", "ATM Withdrawal", "100.00", "", "4447.98", "****1234", ""),
    ("01/23/2024", "Pharmacy", "23.45", "", "4424.53", "****1234", ""),
    ("01/25/2024", "Check #1001", "500.00", "", "3924.53", "****1234", "1001"),
    ("01/26/2024", "Interest Payment", "", "2.50", "3927.03", "****1234", ""),
    ("01/28/2024", "Gym Membership", "50.00", "", "3877.03", "****1234", ""),
    ("01/29/2024", "Coffee Shop", "5.75", "", "3871.28", "****1234", ""),
    ("01/30/2024", "Grocery Store", "92.15", "", "3779.13", "****1234", ""),
    ("01/31/2024", "Rent Payment", "1500.00", "", "2279.13", "****1234", ""),
]

for trans in transactions:
    row = TableRow()
    for i, value in enumerate(trans):
        cell = TableCell(valuetype="string" if value else "string")
        if value:
            cell.addElement(P(text=value))
        row.addElement(cell)
    table.addElement(row)

# Footer row: Transaction count
footer_row = TableRow()
cell = TableCell()
cell.addElement(P(text=f"Total Transactions: {len(transactions)}"))
cell.setAttribute('numbercolumnsspanned', '7')
footer_row.addElement(cell)
for _ in range(6):
    footer_row.addElement(TableCell())
table.addElement(footer_row)

doc.spreadsheet.addElement(table)

# Save the file
doc.save("/home/ga/Documents/bank_export_messy.ods")
print("✅ Created messy bank export ODS file")
PYEOF

# Create format requirements text file
cat > /home/ga/Documents/format_requirements.txt << 'EOF'
CSV FORMAT REQUIREMENTS FOR BUDGET SOFTWARE IMPORT
==================================================

Required columns (in exact order):
1. Date (YYYY-MM-DD format)
2. Description (text)
3. Amount (number, negative for expenses, positive for income)
4. Category (can be empty)

Requirements:
- Exactly 4 columns, no more, no less
- Column headers must match exactly (case-sensitive)
- Date format must be YYYY-MM-DD (ISO 8601)
- Amount must be numeric with up to 2 decimal places
- Expenses should be negative numbers
- Income should be positive numbers
- No extra rows above header or below data
- No empty rows
- CSV encoding: UTF-8
- Delimiter: comma

Example output:
Date,Description,Amount,Category
2024-01-15,Coffee Shop,-4.50,
2024-01-15,Paycheck,2500.00,
EOF

# Set correct permissions
sudo chown ga:ga /home/ga/Documents/bank_export_messy.ods
sudo chown ga:ga /home/ga/Documents/format_requirements.txt
sudo chmod 666 /home/ga/Documents/bank_export_messy.ods
sudo chmod 666 /home/ga/Documents/format_requirements.txt

echo "✅ Created format requirements document"

# Launch LibreOffice Calc with the messy bank export
echo "Launching LibreOffice Calc..."
su - ga -c "DISPLAY=:1 libreoffice --calc --norestore /home/ga/Documents/bank_export_messy.ods > /tmp/calc_bank_task.log 2>&1 &"

# Wait for LibreOffice to start
if ! wait_for_process "soffice" 15; then
    echo "ERROR: LibreOffice failed to start"
    cat /tmp/calc_bank_task.log || true
    # Don't exit, continue
fi

# Wait for window to appear
if ! wait_for_window "LibreOffice Calc" 90; then
    echo "ERROR: LibreOffice Calc window did not appear"
    # Don't exit, continue
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
        
        # Position at A1
        safe_xdotool ga :1 key ctrl+Home
        sleep 0.3
    fi
fi

# Open the format requirements in text editor for reference
echo "Opening format requirements..."
su - ga -c "DISPLAY=:1 xdg-open /home/ga/Documents/format_requirements.txt > /dev/null 2>&1 &" || true
sleep 1

echo "=== Bank Import Formatter Task Setup Complete ==="
echo ""
echo "📋 TASK INSTRUCTIONS:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Transform the messy bank export into required CSV format:"
echo ""
echo "REQUIRED OUTPUT FORMAT:"
echo "  Date,Description,Amount,Category"
echo "  2024-01-15,Coffee Shop,-4.50,"
echo "  2024-01-15,Paycheck,2500.00,"
echo ""
echo "STEPS TO COMPLETE:"
echo "  1. Remove title rows (bank name, export date)"
echo "  2. Delete footer row (transaction count)"
echo "  3. Rename columns to: Date, Description, Amount, Category"
echo "  4. Convert dates from MM/DD/YYYY to YYYY-MM-DD"
echo "  5. Combine Debit/Credit into Amount (expenses negative)"
echo "  6. Delete extra columns (Balance, Account#, Check#)"
echo "  7. Add empty Category column"
echo "  8. Export as CSV: File → Save As → Text CSV"
echo "  9. Save as: transactions_formatted.csv"
echo ""
echo "See format_requirements.txt for full specification"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"