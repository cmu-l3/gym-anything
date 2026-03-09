#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Co-Parenting Expense Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with three blank sheets
SHEET_PATH="$WORKSPACE_DIR/Custody_Recon_March_2024.xlsx"

cat > /tmp/create_coparenting_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Remove default sheet and create three named sheets
if 'Sheet' in wb.sheetnames:
    del wb['Sheet']

# Sheet 1: Custody Days
ws_custody = wb.create_sheet("Custody Days", 0)
ws_custody['A1'] = "March 2024 Custody Calendar"
ws_custody['A1'].font = Font(bold=True, size=14)
ws_custody['A2'] = ""
ws_custody['A3'] = "Instructions: Track who had custody each day"
ws_custody['A4'] = "Your custody days: 1-4, 8-11, 15-18, 22-25, 29-31"
ws_custody['A5'] = "Ex's custody days: 5-7, 12-14, 19-21, 26-28"
ws_custody['A6'] = "Split custody: Day 16 (0.5 each)"
ws_custody['A7'] = ""
ws_custody['A8'] = "Date"
ws_custody['B8'] = "Day"
ws_custody['C8'] = "Custody (You/Ex/Split)"
ws_custody['A8'].font = Font(bold=True)
ws_custody['B8'].font = Font(bold=True)
ws_custody['C8'].font = Font(bold=True)

# Add dates for March 2024
days = ['Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun',
        'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed',
        'Thu', 'Fri', 'Sat', 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun']

for i in range(1, 32):
    row = 8 + i
    ws_custody[f'A{row}'] = f"3/{i}/2024"
    ws_custody[f'B{row}'] = days[i-1]

# Add summary section
ws_custody['A41'] = ""
ws_custody['A42'] = "Custody Summary:"
ws_custody['A42'].font = Font(bold=True, size=12)
ws_custody['A43'] = "Your Total Days:"
ws_custody['A44'] = "Ex's Total Days:"
ws_custody['A45'] = "Split Days (0.5 each):"
ws_custody['A46'] = ""
ws_custody['A47'] = "Your Percentage:"
ws_custody['A48'] = "Ex's Percentage:"
ws_custody['A49'] = ""
ws_custody['A50'] = "Agreement specifies 60/40 split"

# Sheet 2: Expenses
ws_expenses = wb.create_sheet("Expenses", 1)
ws_expenses['A1'] = "March 2024 Expense Log"
ws_expenses['A1'].font = Font(bold=True, size=14)
ws_expenses['A2'] = ""
ws_expenses['A3'] = "Enter the following 8 expenses:"
ws_expenses['A4'] = "1. 3/2 - Medical - Dr. Chen copay for Emma's ear infection - $35 - 50% split"
ws_expenses['A5'] = "2. 3/5 - Educational - Liam's school trip to museum - $15 - 50% split"
ws_expenses['A6'] = "3. 3/9 - Extracurricular - Emma's soccer league spring fee - $125 - 50% split"
ws_expenses['A7'] = "4. 3/12 - Disputed - Soccer snacks for team (your week) - $18 - 100% your responsibility"
ws_expenses['A8'] = "5. 3/16 - Medical - Prescription antibiotic for Emma - $12 - 50% split"
ws_expenses['A9'] = "6. 3/20 - Educational - Liam's required calculator for math - $28 - 50% split"
ws_expenses['A10'] = "7. 3/23 - Extracurricular - Emma's soccer tournament registration - $40 - 50% split"
ws_expenses['A11'] = "8. 3/27 - Routine - Haircuts for both kids - $35 - 100% your responsibility"
ws_expenses['A12'] = ""
ws_expenses['A13'] = "Date"
ws_expenses['B13'] = "Category"
ws_expenses['C13'] = "Description"
ws_expenses['D13'] = "Amount"
ws_expenses['E13'] = "Your Share"
ws_expenses['F13'] = "Notes"

for col in ['A', 'B', 'C', 'D', 'E', 'F']:
    ws_expenses[f'{col}13'].font = Font(bold=True)

# Sheet 3: Summary
ws_summary = wb.create_sheet("Summary", 2)
ws_summary['A1'] = "March 2024 Co-Parenting Expense Summary"
ws_summary['A1'].font = Font(bold=True, size=14)
ws_summary['A2'] = ""
ws_summary['A3'] = "Instructions: Create formulas to calculate totals and reimbursement"
ws_summary['A4'] = ""
ws_summary['A5'] = "Total Expenses Paid by You:"
ws_summary['A6'] = "Extraordinary Expenses (50/50 items):"
ws_summary['A7'] = "Your 50% Share of Extraordinary:"
ws_summary['A8'] = "Routine Expenses (Your Responsibility):"
ws_summary['A9'] = ""
ws_summary['A10'] = "Amount Ex Owes You:"
ws_summary['A10'].font = Font(bold=True, size=12, color="0000FF")
ws_summary['A11'] = ""
ws_summary['A12'] = "Custody Day Verification:"
ws_summary['A13'] = "Your Actual Days:"
ws_summary['A14'] = "Agreement Days (60% of 31):"
ws_summary['A15'] = "Difference from Agreement:"

# Set column widths for better readability
ws_custody.column_dimensions['A'].width = 15
ws_custody.column_dimensions['B'].width = 10
ws_custody.column_dimensions['C'].width = 20

ws_expenses.column_dimensions['A'].width = 12
ws_expenses.column_dimensions['B'].width = 18
ws_expenses.column_dimensions['C'].width = 35
ws_expenses.column_dimensions['D'].width = 12
ws_expenses.column_dimensions['E'].width = 12
ws_expenses.column_dimensions['F'].width = 30

ws_summary.column_dimensions['A'].width = 35
ws_summary.column_dimensions['B'].width = 15

wb.save(sys.argv[1])
print(f"Co-parenting spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_coparenting_sheet.py
python3 /tmp/create_coparenting_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_coparenting_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_coparenting_task.log || true
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

echo "=== Co-Parenting Expense Reconciliation Task Setup Complete ==="
echo ""
echo "📋 TASK OVERVIEW:"
echo "You're preparing a monthly expense reconciliation for co-parenting."
echo "Your ex-partner has disputed claims before, so this needs to be organized and clear."
echo ""
echo "📝 REQUIRED ACTIONS:"
echo ""
echo "SHEET 1 - Custody Days:"
echo "  • Fill in custody column (C) for each day in March 2024"
echo "    - Enter 'You' for days: 1-4, 8-11, 15-18, 22-25, 29-31"
echo "    - Enter 'Ex' for days: 5-7, 12-14, 19-21, 26-28"
echo "    - Enter 'Split' for day: 16 (transition day)"
echo "  • Calculate total days (count You=1, Ex=1, Split=0.5 for each parent)"
echo "  • Calculate custody percentages"
echo ""
echo "SHEET 2 - Expenses:"
echo "  • Enter all 8 expenses with dates, categories, descriptions, amounts"
echo "  • Calculate 'Your Share' (50% for extraordinary, 100% for routine/disputed)"
echo ""
echo "SHEET 3 - Summary:"
echo "  • Create formulas to sum total expenses"
echo "  • Calculate extraordinary expenses (Medical + Educational + Extracurricular)"
echo "  • Calculate your 50% share"
echo "  • Calculate routine expenses (Disputed + Routine categories)"
echo "  • Calculate reimbursement: Ex's 50% of extraordinary expenses"
echo "  • Reference custody days from Sheet 1"
echo ""
echo "💾 Save the spreadsheet when complete (Ctrl+S)"
echo ""
echo "Expected Results:"
echo "  - Extraordinary expenses: $255 (35+15+125+12+28+40)"
echo "  - Your 50% of extraordinary: $127.50"
echo "  - Routine/Disputed: $53 (18+35)"
echo "  - Total paid by you: $308"
echo "  - Ex owes you: $127.50"
echo "  - Your custody days: 17.5 out of 31 (56.5%)"