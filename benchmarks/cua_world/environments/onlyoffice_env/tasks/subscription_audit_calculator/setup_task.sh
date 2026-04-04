#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Subscription Audit Calculator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the subscription audit spreadsheet with starter data
SHEET_PATH="$WORKSPACE_DIR/subscriptions_raw.xlsx"

cat > /tmp/create_subscription_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Subscription Audit"

# Headers for provided data (columns A-E)
ws['A1'] = "Service Name"
ws['B1'] = "Billing Cycle"
ws['C1'] = "Cost"
ws['D1'] = "Shared"
ws['E1'] = "Num People"

# Style headers
header_font = Font(bold=True, size=11)
for cell in ['A1', 'B1', 'C1', 'D1', 'E1']:
    ws[cell].font = header_font
    ws[cell].alignment = Alignment(horizontal='center')

# Sample subscription data (realistic, varied billing cycles)
# Format: [Service Name, Billing Cycle, Cost, Shared, Num People]
data = [
    ["Netflix Standard", "Monthly", 15.49, "Yes", 3],
    ["Spotify Family", "Monthly", 16.99, "Yes", 4],
    ["Adobe Creative Cloud", "Annual", 599.88, "No", 1],
    ["YouTube Premium", "Monthly", 11.99, "Yes", 2],
    ["Amazon Prime", "Annual", 139.00, "Yes", 2],
    ["Disney+", "Monthly", 10.99, "No", ""],
    ["Planet Fitness", "Monthly", 24.99, "No", ""],
    ["Audible", "Monthly", 14.95, "No", 1],
    ["Cloud Storage", "Annual", 99.99, "No", ""],
    ["Meal Kit Service", "Quarterly", 179.97, "Yes", 2],
    ["Language App", "Monthly", 12.99, "No", 1],
]

# Populate data rows
for idx, row in enumerate(data, start=2):
    ws[f'A{idx}'] = row[0]
    ws[f'B{idx}'] = row[1]
    ws[f'C{idx}'] = row[2]
    ws[f'D{idx}'] = row[3]
    # Handle empty Num People (some subscriptions are not shared or implicitly 1 person)
    ws[f'E{idx}'] = row[4] if row[4] not in ["", 1] else ""

# Apply number formatting to Cost column
for row in range(2, 13):
    ws[f'C{row}'].number_format = '$#,##0.00'

# Adjust column widths for readability
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 16
ws.column_dimensions['H'].width = 12

# Add instruction hints in rows 14-15
ws['A14'] = "Instructions:"
ws['A14'].font = Font(bold=True, size=10, italic=True)
ws['A15'] = "Add formulas in columns F-H, enter decisions, and calculate summary totals below"
ws['A15'].font = Font(size=9, italic=True)

wb.save(sys.argv[1])
print(f"✅ Subscription audit spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_subscription_sheet.py
python3 /tmp/create_subscription_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"
ls -lh "$SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_subscription_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_subscription_task.log || true
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

echo "=== Subscription Audit Calculator Task Setup Complete ==="
echo ""
echo "📊 SCENARIO:"
echo "Maya is auditing her subscription spending. She has 11 subscriptions with"
echo "different billing cycles (Monthly/Annual/Quarterly) and some are shared."
echo ""
echo "📝 YOUR TASKS:"
echo ""
echo "1. ADD COLUMN HEADERS (Row 1):"
echo "   - F1: 'Annual Cost'"
echo "   - G1: 'Cost Per Person'"
echo "   - H1: 'Decision'"
echo ""
echo "2. CREATE ANNUAL COST FORMULAS (Column F, rows 2-12):"
echo "   - IF Monthly: Cost × 12"
echo "   - IF Annual: Cost as-is"
echo "   - IF Quarterly: Cost × 4"
echo "   Example: =IF(B2=\"Monthly\",C2*12,IF(B2=\"Annual\",C2,IF(B2=\"Quarterly\",C2*4,0)))"
echo ""
echo "3. CREATE COST PER PERSON FORMULAS (Column G, rows 2-12):"
echo "   - IF Num People > 1: Annual Cost ÷ Num People"
echo "   - OTHERWISE: Annual Cost"
echo "   Handle empty cells (treat as 1 person)"
echo "   Example: =IF(E2>1,F2/E2,F2) or =F2/MAX(E2,1)"
echo ""
echo "4. ENTER DECISIONS (Column H):"
echo "   - Mark at least 6 subscriptions as 'Keep' or 'Cancel'"
echo "   - At least 2 must be 'Cancel'"
echo "   - At least 3 must be 'Keep'"
echo ""
echo "5. CALCULATE SUMMARY STATISTICS (below data, e.g. rows 17-20):"
echo "   - Total Annual Spending: =SUM(F2:F12)"
echo "   - Amount to Cancel: =SUMIF(H2:H12,\"Cancel\",F2:F12)"
echo "   - Remaining if Keeping: =Total - Amount to Cancel"
echo "   - Annual Savings: =Amount to Cancel"
echo ""
echo "6. SAVE THE FILE (Ctrl+S)"
echo ""
echo "💡 TIP: Use currency formatting for cost columns for better readability"