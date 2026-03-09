#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Estate Inventory Probate Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the estate documents text file with messy information
ESTATE_DOCS="$WORKSPACE_DIR/estate_documents.txt"

cat > "$ESTATE_DOCS" << 'ESTATEEOF'
ESTATE OF MARGARET ELLEN HAYES - DOCUMENTS RECEIVED

BANK ACCOUNTS:
- First National Bank checking account #4521, statement shows balance $8,450.23 as of date of death
- First National savings account #4522, balance $15,200.00
- Credit Union account #88392, balance $3,100.50

INVESTMENT ACCOUNTS:
- Vanguard IRA account #555-123789, latest statement value $47,850.00
- Charles Schwab taxable account #9834-2231, current value approx $12,300

REAL PROPERTY:
- Primary residence: 145 Oak Street (deed in box), property tax assessment value $185,000
- Undeveloped lot: Parcel #45-023 County Road 19, assessment $22,000

VEHICLES:
- 2015 Honda CR-V (title in box), KBB estimate $11,500
- 2008 Toyota Camry (title in box), KBB estimate $4,200

PERSONAL PROPERTY:
- Jewelry (appraisal from 2019): $8,500
- Furniture and household items (estimated): $5,000

DEBTS AND LIABILITIES:
- Mortgage on 145 Oak Street, balance per last statement: $68,400
- Capital One credit card #5521, balance $3,245.18
- Medical bills from final illness: $2,180.00
- Funeral expenses paid by estate: $6,500.00

NOTES:
- Some investment values are approximate (market fluctuates)
- Property values are from tax assessor, may differ from market value
- Need to file this inventory with probate court by June 15th
ESTATEEOF

chown ga:ga "$ESTATE_DOCS"
echo "✅ Estate documents created at: $ESTATE_DOCS"

# Create a minimal starter spreadsheet with just column headers
SHEET_PATH="$WORKSPACE_DIR/Estate_Inventory.xlsx"

cat > /tmp/create_estate_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Estate Inventory"

# Add a title and some basic structure hints
ws['A1'] = "ESTATE OF MARGARET ELLEN HAYES"
ws['A1'].font = Font(size=14, bold=True)

ws['A3'] = "Item Description"
ws['B3'] = "Value"
ws['A3'].font = Font(bold=True)
ws['B3'].font = Font(bold=True)

# Set column widths for readability
ws.column_dimensions['A'].width = 40
ws.column_dimensions['B'].width = 15

wb.save(sys.argv[1])
print(f"Estate inventory template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_estate_sheet.py
python3 /tmp/create_estate_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Estate inventory template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_estate_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_estate_task.log || true
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

# Open the source document in a text editor for reference
# Launch gedit with the estate documents in a separate window
su - ga -c "DISPLAY=:1 gedit '$ESTATE_DOCS' > /tmp/gedit_estate.log 2>&1 &" || true
sleep 2

echo "=== Estate Inventory Probate Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "   You are executor of your late aunt Margaret's estate."
echo "   The probate court requires a complete inventory within 90 days."
echo ""
echo "📁 FILES:"
echo "   Source data: $ESTATE_DOCS (opened in text editor)"
echo "   Target spreadsheet: $SHEET_PATH (opened in ONLYOFFICE)"
echo ""
echo "📝 YOUR TASK:"
echo "   1. Read the estate documents to identify all assets and liabilities"
echo "   2. Create organized sections in the spreadsheet:"
echo "      - ASSETS section (bank accounts, investments, property, vehicles, personal property)"
echo "      - LIABILITIES section (mortgage, credit card, medical bills, funeral)"
echo "      - SUMMARY section with calculations"
echo "   3. Enter ALL values from the source document"
echo "   4. Create formulas for:"
echo "      - Total Assets (use SUM formula)"
echo "      - Total Liabilities (use SUM formula)"
echo "      - Net Estate Value (Assets minus Liabilities)"
echo "   5. Format professionally for court submission"
echo "   6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "✅ Expected Results:"
echo "   Total Assets: $323,100.73"
echo "   Total Liabilities: $80,325.18"
echo "   Net Estate Value: $242,775.55"
echo ""
echo "⚠️  IMPORTANT: Use formulas for all calculations, not hard-coded values!"