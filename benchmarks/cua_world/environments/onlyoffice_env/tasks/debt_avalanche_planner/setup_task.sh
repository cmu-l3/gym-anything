#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Debt Avalanche Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with debt data
SHEET_PATH="$WORKSPACE_DIR/debt_payoff_plan.xlsx"

cat > /tmp/create_debt_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Debt Payoff Plan"

# Add title
ws['A1'] = "Debt Avalanche Payoff Strategy"
ws['A1'].font = Font(size=14, bold=True)

# Add column headers
headers = ['Debt Name', 'Balance', 'Interest Rate', 'Minimum Payment', 'Monthly Budget Available', 'Priority Rank']
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=2, column=col_idx)
    cell.value = header
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add debt data (5 debts as specified in task)
debts = [
    ['Credit Card A', 4200, 0.2399, 125, '', '[Rank here: 1-5]'],
    ['Credit Card B', 2800, 0.185, 85, '', '[Rank here: 1-5]'],
    ['Personal Loan', 6500, 0.12, 180, '', '[Rank here: 1-5]'],
    ['Car Loan', 9200, 0.065, 245, '', '[Rank here: 1-5]'],
    ['Student Loan', 3100, 0.0425, 65, '', '[Rank here: 1-5]']
]

for row_idx, debt in enumerate(debts, start=3):
    ws.cell(row=row_idx, column=1, value=debt[0])  # Debt Name
    ws.cell(row=row_idx, column=2, value=debt[1])  # Balance
    ws.cell(row=row_idx, column=3, value=debt[2])  # Interest Rate
    ws.cell(row=row_idx, column=4, value=debt[3])  # Minimum Payment
    ws.cell(row=row_idx, column=5, value=debt[4])  # Empty for now
    ws.cell(row=row_idx, column=6, value=debt[5])  # Priority placeholder

# Format currency and percentage columns
for row in range(3, 8):
    ws.cell(row=row, column=2).number_format = '"$"#,##0'  # Balance
    ws.cell(row=row, column=3).number_format = '0.00%'     # Interest Rate
    ws.cell(row=row, column=4).number_format = '"$"#,##0'  # Minimum Payment

# Add summary section
ws['A9'] = "=== SUMMARY ==="
ws['A9'].font = Font(bold=True)

ws['A10'] = "Total Debt:"
ws['B10'] = "[Add SUM formula here for all balances]"

ws['A11'] = "Total Minimum Payments:"
ws['B11'] = "[Add SUM formula here for all minimum payments]"

ws['A12'] = "Monthly Budget Available:"
ws['B12'] = 800

ws['A13'] = "Extra for Highest Priority:"
ws['B13'] = "[Calculate: Budget - Total Minimums]"

# Add instructions
ws['A15'] = "INSTRUCTIONS:"
ws['A15'].font = Font(bold=True, italic=True)
ws['A16'] = "1. In column F (Priority Rank), assign ranks 1-5 where 1 = highest interest rate"
ws['A17'] = "2. In B10, add formula: =SUM(B3:B7) for total debt"
ws['A18'] = "3. In B11, add formula: =SUM(D3:D7) for total minimum payments"
ws['A19'] = "4. In B13, add formula: =B12-B11 for extra payment amount"
ws['A20'] = "5. HIGHLIGHT the entire row of your Priority 1 debt (highest interest)"
ws['A21'] = "6. Save the file (Ctrl+S)"

# Adjust column widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 18
ws.column_dimensions['E'].width = 25
ws.column_dimensions['F'].width = 15

wb.save(sys.argv[1])
print(f"Debt payoff spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_debt_sheet.py
python3 /tmp/create_debt_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_debt_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_debt_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Debt Avalanche Planner Task Setup Complete ==="
echo "📝 Scenario: Jordan is creating a debt payoff plan using the avalanche method"
echo ""
echo "✅ Spreadsheet contains 5 debts:"
echo "   - Credit Card A: \$4,200 @ 23.99% (should be Priority 1)"
echo "   - Credit Card B: \$2,800 @ 18.5%"
echo "   - Personal Loan: \$6,500 @ 12.0%"
echo "   - Car Loan: \$9,200 @ 6.5%"
echo "   - Student Loan: \$3,100 @ 4.25%"
echo ""
echo "📋 Tasks to complete:"
echo "   1. Assign priority ranks (1-5) in column F based on interest rates"
echo "   2. Add SUM formula in B10 for total debt"
echo "   3. Add SUM formula in B11 for total minimum payments"
echo "   4. Add formula in B13 for extra payment amount"
echo "   5. Highlight the Priority 1 debt row (Credit Card A)"
echo "   6. Save (Ctrl+S)"