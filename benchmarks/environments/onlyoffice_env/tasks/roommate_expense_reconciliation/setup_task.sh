#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Roommate Expense Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with March bills and notes
SHEET_PATH="$WORKSPACE_DIR/march_bills_raw.xlsx"

cat > /tmp/create_roommate_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "March Bills"

# Headers
ws['A1'] = 'Bill Name'
ws['B1'] = 'Amount'
ws['C1'] = 'Due Date'

# Make headers bold with light blue background
header_fill = PatternFill(start_color="D9E8F5", end_color="D9E8F5", fill_type="solid")
for cell in ['A1', 'B1', 'C1']:
    ws[cell].font = Font(bold=True, size=11)
    ws[cell].fill = header_fill
    ws[cell].alignment = Alignment(horizontal='center')

# Bill data - March 2024
bills = [
    ('Rent', 2400, 'April 1'),
    ('Internet', 52, 'March 28'),
    ('Electricity', 87, 'March 30'),
    ('Gas', 43, 'March 30'),
    ('Water', 28, 'March 25')
]

row = 2
for bill_name, amount, due_date in bills:
    ws[f'A{row}'] = bill_name
    ws[f'B{row}'] = amount
    ws[f'C{row}'] = due_date
    row += 1

# Set column widths for readability
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12

# Add a blank row
row += 1

# Add notes section
ws[f'A{row}'] = 'IMPORTANT NOTES:'
ws[f'A{row}'].font = Font(bold=True, size=12, color="C00000")
row += 1

notes = [
    "- Jordan pre-paid $60 for internet via Venmo, but actual bill is $52 (overpaid by $8)",
    "- February utility was estimated at $180 but actual bill came in at $165",
    "  → We overcharged everyone $3.75 each last month (need to credit back)",
    "- Alex owes $40 from February for shared Amazon Prime subscription (forgot to include)",
    "- Sam is traveling abroad and asked you to cover their March share",
    "  → Sam will pay back in April",
    "",
    "YOUR TASK:",
    "Create a new sheet to calculate who owes what for March, accounting for all adjustments."
]

for note in notes:
    ws[f'A{row}'] = note
    if note.startswith("YOUR TASK:"):
        ws[f'A{row}'].font = Font(bold=True, size=11, color="0070C0")
    row += 1

wb.save(sys.argv[1])
print(f"Roommate expense spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_roommate_sheet.py
python3 /tmp/create_roommate_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_roommate_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_roommate_task.log || true
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

echo "=== Roommate Expense Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   You live with 3 roommates (Alex, Jordan, Sam) and it's end-of-month reconciliation."
echo ""
echo "📝 TASK REQUIREMENTS:"
echo "   1. Create a new sheet (Sheet2) named 'March Reconciliation'"
echo "   2. Calculate total March bills: \$2400 + \$52 + \$87 + \$43 + \$28 = \$2610"
echo "   3. Calculate per-person base share: \$2610 ÷ 4 = \$652.50"
echo "   4. Apply adjustments for each roommate:"
echo "      • You: -\$3.75 (Feb credit)"
echo "      • Alex: -\$3.75 (Feb credit) + \$40 (Feb debt) = +\$36.25 adjustment"
echo "      • Jordan: -\$3.75 (Feb credit) - \$8 (internet overpay) = -\$11.75 adjustment"
echo "      • Sam: Deferred to April (note this)"
echo "   5. Create summary table with: Name, Base Share, Adjustments, Final Amount"
echo "   6. Format with bold headers and currency formatting"
echo "   7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "🎯 EXPECTED FINAL AMOUNTS:"
echo "   • Alex owes you: \$688.75"
echo "   • Jordan owes you: \$640.75"
echo "   • Sam: \$0 (deferred to April - add note)"