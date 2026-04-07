#!/bin/bash
echo "=== Setting up bank_reconciliation task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/november_reconciliation.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate a mathematically balanced reconciliation dataset
python3 << 'PYEOF'
import openpyxl
from openpyxl.styles import Font, PatternFill, Alignment

wb = openpyxl.Workbook()
ws_ledger = wb.active
ws_ledger.title = "Ledger"
ws_bank = wb.create_sheet("Bank_Statement")

headers = ["Date", "Transaction_Ref", "Description", "Amount"]
ws_ledger.append(headers)
ws_bank.append(headers)

# Common transactions (Exist in both)
common = [
    ("2023-11-01", "TXN-1001", "Opening Balance", 10000.00),
    ("2023-11-02", "TXN-1002", "Client Payment - Corp A", 2500.00),
    ("2023-11-05", "TXN-1003", "Office Supplies", -350.00),
    ("2023-11-10", "TXN-1004", "Software Subscriptions", -150.00),
    ("2023-11-15", "TXN-1005", "Client Payment - Corp B", 3200.00),
    ("2023-11-20", "TXN-1006", "Utility Bill", -200.00),
    ("2023-11-25", "TXN-1007", "Consulting Fees", -300.00),
] # Sum = 14,700

# Ledger Only (Outstanding)
ledger_only = [
    ("2023-11-28", "TXN-2001", "Client Payment - Corp C", 800.00),
    ("2023-11-29", "TXN-2002", "Vendor Payment - Cleaning", -500.00),
] # Sum = 300

# Bank Only (Unrecorded)
bank_only = [
    ("2023-11-30", "TXN-3001", "Monthly Interest", 150.00),
    ("2023-11-30", "TXN-3002", "Account Maintenance Fee", -50.00),
] # Sum = 100

ledger_txns = common + ledger_only
ledger_txns.sort(key=lambda x: x[0])

bank_txns = common + bank_only
bank_txns.sort(key=lambda x: x[0])

for txn in ledger_txns:
    ws_ledger.append(txn)
    
for txn in bank_txns:
    ws_bank.append(txn)

header_font = Font(bold=True)
header_fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")

for ws in [ws_ledger, ws_bank]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')
    
    ws.column_dimensions['A'].width = 15
    ws.column_dimensions['B'].width = 20
    ws.column_dimensions['C'].width = 35
    ws.column_dimensions['D'].width = 15
    
    for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=4, max_col=4):
        for cell in row:
            cell.number_format = '#,##0.00'

wb.save("/home/ga/Documents/november_reconciliation.xlsx")
print("Created mathematically balanced reconciliation data")
PYEOF

chown ga:ga "$FILE_PATH" 2>/dev/null || true

# Start WPS Spreadsheet if not running
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    sleep 5
fi

# Focus the window and maximize
for i in {1..10}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "WPS Spreadsheet"; then
        DISPLAY=:1 wmctrl -a "WPS Spreadsheet" 2>/dev/null || true
        DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
        break
    fi
    sleep 1
done

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="