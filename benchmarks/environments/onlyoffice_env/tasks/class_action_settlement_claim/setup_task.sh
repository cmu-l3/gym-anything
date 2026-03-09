#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Class Action Settlement Claim Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with pre-populated data
SHEET_PATH="$WORKSPACE_DIR/class_action_claims.xlsx"

cat > /tmp/create_settlement_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "SettlementClaims"

# Add headers (Row 1)
headers = [
    "Lawsuit Name",
    "Product/Service", 
    "Purchase Date",
    "Amount Paid",
    "Have Proof?",
    "Est. Recovery",
    "Claim Deadline",
    "Status"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='left')

# Pre-populate data (Rows 2-5)
# Row 2: TechPhone Battery (complete except Est. Recovery and Status)
ws['A2'] = "TechPhone Battery"
ws['B2'] = "TechPhone X2"
ws['C2'] = "03/15/2020"
ws['D2'] = "$799.00"
ws['E2'] = "Yes"
ws['F2'] = ""  # Agent needs to fill: $65.00
ws['G2'] = "02/28/2025"
ws['H2'] = ""  # Agent needs to fill: Ready to file

# Row 3: StreamFlix Overcharge (missing Est. Recovery and Status)
ws['A3'] = "StreamFlix Overcharge"
ws['B3'] = "Premium Plan"
ws['C3'] = "06/01/2021"
ws['D3'] = "$180.00"
ws['E3'] = "No"
ws['F3'] = ""  # Agent needs to fill: $10.00
ws['G3'] = "03/15/2025"
ws['H3'] = ""  # Agent needs to fill: Ready to file

# Row 4: QuickGro False Ad (missing Purchase Date, Amount Paid, and other fields)
ws['A4'] = "QuickGro False Ad"
ws['B4'] = "Lawn Fertilizer 50lb"
ws['C4'] = ""  # Agent needs to fill: 06/15/2021
ws['D4'] = ""  # Agent needs to fill: $42.00
ws['E4'] = ""  # Agent needs to fill: Yes
ws['F4'] = ""  # Agent needs to fill: $30.00
ws['G4'] = "02/20/2025"
ws['H4'] = ""  # Agent needs to fill: Ready to file

# Row 5: DataBank Breach (missing Est. Recovery)
ws['A5'] = "DataBank Breach"
ws['B5'] = "Online Banking Account"
ws['C5'] = "11/10/2022"
ws['D5'] = "$0.00"
ws['E5'] = "Yes"
ws['F5'] = ""  # Agent needs to fill: $125.00
ws['G5'] = "03/31/2025"
ws['H5'] = ""  # Agent needs to fill: Ready to file

# Note: Agent needs to add Row 6 (second QuickGro purchase)
# Note: Agent needs to add Row 7 (TOTAL with SUM formula)

# Set column widths for readability
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 15
ws.column_dimensions['H'].width = 15

wb.save(sys.argv[1])
print(f"Settlement claims spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_settlement_sheet.py
python3 /tmp/create_settlement_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Create the settlement notes reference file
NOTES_PATH="$WORKSPACE_DIR/settlement_notes.txt"

cat > "$NOTES_PATH" << 'NOTESEOF'
SETTLEMENT RECOVERY ESTIMATES:
- TechPhone Battery: $45-65 per device with proof, $25 without
- StreamFlix Overcharge: 15% refund of total paid with proof, $10 without  
- QuickGro False Ad: $30 per bag purchased (proof required)
- DataBank Breach: Flat $125 identity monitoring credit (proof of account required)

YOUR PURCHASE HISTORY CHECK:
- TechPhone X2: Yes, bought March 2020, have email confirmation
- StreamFlix: Yes, subscribed 2021-2023, but can't find records
- QuickGro: Yes, bought TWO bags in summer 2021, have receipt
- DataBank: Yes, had account since 2018, affected by breach

NOTES:
- TechPhone claim qualifies for HIGH recovery ($65) because you have proof
- StreamFlix claim is WITHOUT proof ($10) - can't find old statements
- QuickGro needs TWO rows (two bags purchased: 06/2021 and 08/2021)
  * First bag: June 15, 2021, cost $42.00
  * Second bag: August 20, 2021, cost $42.00
- DataBank qualifies for full $125

TASK INSTRUCTIONS:
1. Complete missing data in existing rows based on the purchase history
2. Add a NEW ROW for the second QuickGro purchase (August 2021)
3. Calculate Est. Recovery for each claim using the rules above
4. Add a TOTAL row at the end with a SUM formula for total expected recovery
5. Update Status column to "Ready to file" for all claims
6. Save the spreadsheet (Ctrl+S)

EXPECTED TOTAL RECOVERY: $260.00
NOTESEOF

chown ga:ga "$NOTES_PATH"

echo "✅ Settlement notes created at: $NOTES_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_settlement_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_settlement_task.log || true
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

echo "=== Class Action Settlement Claim Task Setup Complete ==="
echo ""
echo "📝 SCENARIO:"
echo "You received settlement notices for 4 class action lawsuits."
echo "Track your claims to maximize recovery before deadlines."
echo ""
echo "📄 FILES:"
echo "  - Spreadsheet: $SHEET_PATH"
echo "  - Reference: $NOTES_PATH"
echo ""
echo "✅ TASKS TO COMPLETE:"
echo "  1. Fill missing data in Row 2 (TechPhone): Est. Recovery = \$65, Status"
echo "  2. Fill missing data in Row 3 (StreamFlix): Est. Recovery = \$10, Status"
echo "  3. Fill missing data in Row 4 (QuickGro): Purchase Date, Amount, Proof, Recovery, Status"
echo "  4. ADD Row 5 (Second QuickGro): All details for August 2021 purchase"
echo "  5. Fill missing data in Row 6 (DataBank - moved down): Est. Recovery = \$125, Status"
echo "  6. ADD Row 7 (TOTAL): Label and SUM formula for total recovery"
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: Open settlement_notes.txt for detailed instructions and recovery amounts"
echo ""