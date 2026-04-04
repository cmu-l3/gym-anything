#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Job Relocation Analyzer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with partial data
SHEET_PATH="$WORKSPACE_DIR/relocation_comparison_draft.xlsx"

cat > /tmp/create_relocation_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
import sys

wb = Workbook()
ws = wb.active
ws.title = "Cost Comparison"

# Set column widths
ws.column_dimensions['A'].width = 30
ws.column_dimensions['B'].width = 5
ws.column_dimensions['C'].width = 5
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 15

# Title
ws['A1'] = "JOB RELOCATION COST COMPARISON"
ws['A1'].font = Font(size=14, bold=True)
ws.merge_cells('A1:G1')
ws['A1'].alignment = Alignment(horizontal='center')

# Headers
ws['D3'] = "DENVER"
ws['E3'] = "AUSTIN"
ws['F3'] = "DIFFERENCE"
ws['G3'] = "DIFFERENCE %"

header_font = Font(bold=True, size=11)
for col in ['D3', 'E3', 'F3', 'G3']:
    ws[col].font = header_font
    ws[col].alignment = Alignment(horizontal='center')

# Monthly expenses header
ws['A4'] = "MONTHLY EXPENSES"
ws['A4'].font = Font(bold=True, size=11)

# Cost categories with data
cost_data = [
    ("Housing (Rent/Mortgage)", 2200, 3100),
    ("Utilities (Electric, Gas, Water)", 180, 220),
    ("Internet & Phone", 120, 120),
    ("Groceries", 550, 580),
    ("Transportation (Gas/Transit)", 200, 140),
    ("Car Insurance", 145, 165),
    ("Health Insurance (after employer)", 200, 200),
    ("Dining Out & Entertainment", 400, 450),
    ("Misc & Personal", 300, 350)
]

row = 5
for category, denver_cost, austin_cost in cost_data:
    ws[f'A{row}'] = category
    ws[f'D{row}'] = denver_cost
    ws[f'E{row}'] = austin_cost
    ws[f'D{row}'].number_format = '$#,##0.00'
    ws[f'E{row}'].number_format = '$#,##0.00'
    row += 1

# Empty row
row = 14

# Total row (formulas to be added by user)
ws['A15'] = "TOTAL MONTHLY"
ws['A15'].font = Font(bold=True)
ws['D15'] = "[Add SUM formula here]"
ws['E15'] = "[Add SUM formula here]"
ws['F15'] = "[Add difference formula]"
ws['G15'] = "[Add percentage formula]"

# Empty row
ws['A16'] = ""

# Annual costs row
ws['A17'] = "ANNUAL COSTS"
ws['A17'].font = Font(bold=True)
ws['D17'] = "[Multiply monthly by 12]"
ws['E17'] = "[Multiply monthly by 12]"

# Empty rows
ws['A18'] = ""

# Salary information header
ws['A19'] = "SALARY INFORMATION"
ws['A19'].font = Font(bold=True, size=11)

ws['A20'] = "Current Salary (Denver)"
ws['D20'] = 85000
ws['D20'].number_format = '$#,##0'

ws['A21'] = "Offered Salary (Austin)"
ws['E21'] = 100000
ws['E21'].number_format = '$#,##0'

ws['A22'] = "State Income Tax Rate"
ws['D22'] = 0.045
ws['E22'] = 0.0
ws['D22'].number_format = '0.0%'
ws['E22'].number_format = '0.0%'

# Empty row
ws['A23'] = ""

# Break-even analysis header
ws['A24'] = "BREAK-EVEN ANALYSIS"
ws['A24'].font = Font(bold=True, size=11)

ws['A25'] = "Break-Even Salary Needed in Austin"
ws['E25'] = "[Calculate: Current Salary * (Austin Total / Denver Total)]"

ws['A26'] = "Real Salary Increase (after CoL)"
ws['E26'] = "[Calculate: Offer - Break-Even]"

# Instructions note
ws['A28'] = "INSTRUCTIONS:"
ws['A28'].font = Font(bold=True, italic=True, size=10)
ws['A29'] = "Complete the formulas in the marked cells to analyze if the job offer"
ws['A30'] = "provides real financial benefit after accounting for cost of living differences."

wb.save(sys.argv[1])
print(f"Relocation comparison spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_relocation_sheet.py
python3 /tmp/create_relocation_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_relocation_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_relocation_task.log || true
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

echo "=== Job Relocation Analyzer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Complete the following formulas:"
echo "  1. D15: =SUM(D5:D13) [Denver total monthly costs]"
echo "  2. E15: =SUM(E5:E13) [Austin total monthly costs]"
echo "  3. F15: =E15-D15 [Difference in monthly costs]"
echo "  4. G15: =(E15-D15)/D15 [Percentage difference]"
echo "  5. D17: =D15*12 [Annual Denver costs]"
echo "  6. E17: =E15*12 [Annual Austin costs]"
echo "  7. E25: =D20*(E15/D15) [Break-even salary in Austin]"
echo "  8. E26: =E21-E25 [Real salary increase after CoL]"
echo ""
echo "Expected results (approximate):"
echo "  - Denver Monthly Total: $4,295"
echo "  - Austin Monthly Total: $5,325"
echo "  - Difference: $1,030"
echo "  - Percentage: ~24%"
echo "  - Break-Even Salary: ~$105,331"
echo "  - Real Increase: ~-$5,331 (actually a loss!)"