#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Conference Reimbursement Claim Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the messy receipt data spreadsheet
RAW_RECEIPTS_PATH="$WORKSPACE_DIR/conference_receipts_raw.xlsx"

cat > /tmp/create_receipts.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Receipts"

# Add headers with basic formatting
headers = ["Date", "Vendor/Description", "Amount CAD", "Receipt#", "Notes"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='left')

# Add messy receipt data (realistic conference travel chaos)
receipts = [
    ("5/18/24", "Air Canada - YYZ to YUL", "$450.00", "R001", "Outbound flight"),
    ("May 18", "Taxi - Aéroport YUL to hotel", "45", "R002", "Split taxi w/ Dr. Chen - paid full amount"),
    ("5/18/24", "Hotel Bonaventure - Night 1", "$195.00", "R003", "Wed checkin"),
    ("Sat May 18", "Dinner - Bistro Laurent", "$52", "", "Includes 2 glasses wine"),
    ("May 19", "Hotel Bonaventure - Night 2", "175.00", "R004", "Thu"),
    ("5/19/24", "Café breakfast", "$18.50", "R005", ""),
    ("May 19", "Lunch - food court", "24", "R006", ""),
    ("5/19/24", "CSCB Conference Registration", "$350.00", "R007", "2-day pass"),
    ("Fri May 19", "Dinner - Restaurant Le Local", "$48.00", "R008", "No alcohol"),
    ("May 20", "Hotel Bonaventure - Night 3", "175.00", "R009", "Fri"),
    ("5/20/24", "Breakfast - hotel buffet", "16.00", "R010", ""),
    ("Sat May 20", "Lunch - conference center", "$28.50", "R011", ""),
    ("May 20", "Cell Biology textbook", "$45", "R012", "Purchased at conference bookstore"),
    ("May 21", "Hotel Bonaventure - Night 4", "175.00", "R013", "Sunday night - personal extension"),
    ("5/21/24", "Air Canada - YUL to YYZ", "445.00", "R014", "Return flight Monday"),
]

for row_idx, receipt in enumerate(receipts, start=2):
    for col_idx, value in enumerate(receipt, start=1):
        ws.cell(row=row_idx, column=col_idx, value=value)

# Add some instructions at the bottom
ws.cell(row=len(receipts) + 3, column=1, value="TASK:")
ws.cell(row=len(receipts) + 4, column=1, value="Create reimbursement claim at: /home/ga/Documents/Spreadsheets/reimbursement_claim_final.xlsx")
ws.cell(row=len(receipts) + 5, column=1, value="Apply university reimbursement rules:")
ws.cell(row=len(receipts) + 6, column=1, value="- Convert CAD to USD at rate 0.74")
ws.cell(row=len(receipts) + 7, column=1, value="- Lodging cap: $180 USD per night")
ws.cell(row=len(receipts) + 8, column=1, value="- Meals cap: $45 USD per day (May 18-21 = 4 days eligible)")
ws.cell(row=len(receipts) + 9, column=1, value="- Flag non-reimbursable: alcohol, personal expenses, books, missing receipt#")
ws.cell(row=len(receipts) + 10, column=1, value="- Split expenses: divide by number of people")

# Set column widths for readability
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 35
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 45

wb.save(sys.argv[1])
print(f"Raw receipts spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_receipts.py
python3 /tmp/create_receipts.py "$RAW_RECEIPTS_PATH"
chown ga:ga "$RAW_RECEIPTS_PATH"

echo "✅ Raw receipts spreadsheet created at: $RAW_RECEIPTS_PATH"

# Launch ONLYOFFICE with the raw receipts spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor with raw receipts..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$RAW_RECEIPTS_PATH' > /tmp/onlyoffice_reimbursement_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_reimbursement_task.log || true
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

echo "=== Conference Reimbursement Claim Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Dr. Jamie Patel attended CSCB conference in Montreal (May 18-21, 2024)"
echo "University has 30-day reimbursement deadline - today is day 26!"
echo "Receipts are messy: mixed formats, French text, some issues"
echo ""
echo "📝 TASK REQUIREMENTS:"
echo "1. Create new file: /home/ga/Documents/Spreadsheets/reimbursement_claim_final.xlsx"
echo "2. Clean and organize the 15 receipts from current file"
echo "3. Add USD conversion column (1 CAD = 0.74 USD)"
echo "4. Categorize: Airfare, Lodging, Ground Transport, Conference Fees, Meals, Other"
echo "5. Apply reimbursement caps:"
echo "   - Lodging: max \$180 USD per night"
echo "   - Meals: max \$45 USD per day (4 days: May 18-21)"
echo "   - Airfare & Conference fees: 100% reimbursable"
echo "6. Flag non-reimbursable items:"
echo "   - Alcohol (dinner with wine)"
echo "   - Personal expenses (Sunday night hotel)"
echo "   - Books"
echo "   - Missing receipt numbers"
echo "7. Handle split taxi expense (divide by 2)"
echo "8. Create summary: Total CAD, Total USD, Eligible Reimbursement, Non-Reimbursable"
echo "9. Use formulas for all calculations"
echo "10. Save the reimbursement claim (Ctrl+S)"
echo ""
echo "Expected eligible reimbursement: ~\$1,050-1,150 USD"