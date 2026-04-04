#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Gig Income Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directories
DOCS_DIR="/home/ga/Documents"
SPREADSHEETS_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$DOCS_DIR"
sudo -u ga mkdir -p "$SPREADSHEETS_DIR"

# Create the messy income notes file
NOTES_PATH="$DOCS_DIR/gig_income_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
GIG WORK INCOME - OCT-DEC 2024
==============================

UBER (Rideshare):
- October: $847.50 (28 hours)
- November: $923.20 (31 hours)  
- December: $765.00 (24 hours)
Gas for Uber: ~$340 total

DOORDASH (Food Delivery):
- October: $612.80 (26 hours)
- November: $701.40 (29 hours)
- December: $558.75 (22 hours)
Gas for DoorDash: ~$215 total

INSTACART (Grocery Delivery):
- October: $523.00 (23 hours)
- November: $589.60 (25 hours)
- December: $634.20 (27 hours)
Gas for Instacart: ~$180 total

NOTES:
- Gas prices varied $3.20-$3.85/gallon
- Phone bill: $65/month (should deduct 30%? = $19.50/month × 3 = $58.50)
- Car insurance: $145/month (maybe deduct 40%?)
- Uber had longest average trips
- DoorDash had most cancellations ugh
- Instacart tips were best in December (holidays!)

TO DO:
[ ] Figure out which platform to focus on in January
[ ] Calculate quarterly tax payment (due Jan 15!)
[ ] Ask accountant about mileage deduction vs actual expenses
EOF

chown ga:ga "$NOTES_PATH"
chmod 644 "$NOTES_PATH"

echo "✅ Income notes created at: $NOTES_PATH"

# Create a copy on Desktop for easy visibility
DESKTOP_DIR="/home/ga/Desktop"
sudo -u ga mkdir -p "$DESKTOP_DIR"
sudo -u ga cp "$NOTES_PATH" "$DESKTOP_DIR/gig_income_notes.txt"

echo "✅ Copy placed on Desktop for easy access"

# Create a blank starter spreadsheet with helpful hints
SHEET_PATH="$SPREADSHEETS_DIR/gig_income_analysis.xlsx"

cat > /tmp/create_starter_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Income Analysis"

# Add instruction header
ws['A1'] = "Gig Income Analysis - Q4 2024"
ws['A1'].font = Font(size=14, bold=True)
ws['A1'].alignment = Alignment(horizontal='left')

ws['A2'] = "Read the income notes from: /home/ga/Documents/gig_income_notes.txt"
ws['A2'].font = Font(size=10, italic=True)

ws['A4'] = "Create your analysis below with columns for:"
ws['A5'] = "Platform | Total Earnings | Hours Worked | Gas Expenses | Profit | etc."
ws['A5'].font = Font(italic=True)

# Leave rest blank for agent to fill

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_starter_sheet.py
python3 /tmp/create_starter_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Open the notes file in a text editor so it's visible
echo "Opening income notes in text editor..."
su - ga -c "DISPLAY=:1 xdg-open '$NOTES_PATH' > /dev/null 2>&1 &" || true
sleep 2

# Launch ONLYOFFICE with the starter spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_gig_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_gig_task.log || true
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

echo "=== Gig Income Reconciliation Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "Maya is a grad student doing gig work across 3 platforms (Uber, DoorDash, Instacart)."
echo "She needs to reconcile her Q4 2024 income for quarterly tax filing (due Jan 15)."
echo ""
echo "📝 TASK:"
echo "  1. Read the income notes from: /home/ga/Documents/gig_income_notes.txt"
echo "  2. Create a summary table in the spreadsheet with:"
echo "     - Platform name (Uber, DoorDash, Instacart)"
echo "     - Total Earnings (sum of Oct+Nov+Dec for each)"
echo "     - Hours Worked (sum of hours for each)"
echo "     - Gas Expenses (total gas for each)"
echo "     - Profit (Earnings - Gas for each)"
echo "  3. Add a TOTAL row that sums all platforms"
echo "  4. Calculate estimated self-employment tax: 15.3% of total profit"
echo "  5. Use formulas (not hardcoded values) for calculations"
echo "  6. Format currency values with $ symbol"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 HINTS:"
echo "  - Uber total: ~$2535, 83 hours, $340 gas"
echo "  - DoorDash total: ~$1873, 77 hours, $215 gas"
echo "  - Instacart total: ~$1747, 75 hours, $180 gas"
echo "  - Total tax owed should be around $829"