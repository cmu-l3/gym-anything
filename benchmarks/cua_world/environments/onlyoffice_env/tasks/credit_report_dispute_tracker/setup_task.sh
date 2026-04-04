#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Credit Report Dispute Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with messy notes
SHEET_PATH="$WORKSPACE_DIR/credit_disputes_template.xlsx"

cat > /tmp/create_dispute_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Sheet 1: Discovered Errors (messy notes - the raw data Sarah collected)
ws1 = wb.active
ws1.title = "Discovered Errors"

# Header row with basic formatting
ws1['A1'] = "Bureau"
ws1['B1'] = "Problem Found"
ws1['C1'] = "Date Pulled"

for cell in ['A1', 'B1', 'C1']:
    ws1[cell].font = Font(bold=True, size=11)
    ws1[cell].fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Messy, realistic notes - as if Sarah typed them quickly while reviewing reports
ws1['A2'] = "Experian"
ws1['B2'] = "Capital One Card - Account #5412XXXX - never opened! Possible fraud?"
ws1['C2'] = "1/15/2025"

ws1['A3'] = "TransUnion"
ws1['B3'] = "Navient Student Loan still showing $4200 balance but I paid it off completely Dec 2023"
ws1['C3'] = "1/15/2025"

ws1['A4'] = "All 3 bureaus"
ws1['B4'] = "Midwest Medical Collections $890 - I settled this Feb 2022 but still shows unpaid on all reports"
ws1['C4'] = "1/15/2025"

ws1['A5'] = "Equifax"
ws1['B5'] = "Wrong address - showing 456 Oak St apt 2B (I moved out in Aug 2023, now at 789 Maple Ave)"
ws1['C5'] = "1/15/2025"

# Add a note at the bottom to add urgency
ws1['A7'] = "Note:"
ws1['A7'].font = Font(italic=True, bold=True)
ws1['B7'] = "Loan officer said these errors are costing me 40-60 FICO points! Must dispute ASAP via certified mail - mortgage rate lock expires in 60 days"
ws1['B7'].font = Font(italic=True)
ws1['B7'].alignment = Alignment(wrap_text=True)

# Column widths
ws1.column_dimensions['A'].width = 15
ws1.column_dimensions['B'].width = 70
ws1.column_dimensions['C'].width = 12

# Sheet 2: Empty Dispute Tracker (agent must build this from scratch)
ws2 = wb.create_sheet("Dispute Tracker")

# Just a hint, not pre-filled headers
ws2['A1'] = "Build your structured tracking system here"
ws2['A1'].font = Font(italic=True, color="808080", size=12)

ws2['A3'] = "Suggested columns: Bureau Name, Error/Account Description, Account Number, Date Discovered, Date Sent,"
ws2['A3'].font = Font(italic=True, size=9, color="A0A0A0")
ws2['A4'] = "Certified Mail Tracking Number, 30-Day Response Deadline (formula), Status, Documentation, Notes"
ws2['A4'].font = Font(italic=True, size=9, color="A0A0A0")

ws2['A6'] = "Remember: Must track all disputes separately. Fair Credit Reporting Act requires response within 30 days."
ws2['A6'].font = Font(italic=True, size=9, color="FF0000")

ws2.column_dimensions['A'].width = 55

wb.save(sys.argv[1])
print(f"Credit dispute tracking template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_dispute_sheet.py
python3 /tmp/create_dispute_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_dispute_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_dispute_task.log || true
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

echo "=== Credit Report Dispute Tracker Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  Sarah is a 32-year-old first-time homebuyer applying for a mortgage."
echo "  She pulled her credit reports and discovered FOUR significant errors"
echo "  costing her 40-60 FICO points. Her mortgage loan officer advised"
echo "  disputing via certified mail (creates legal paper trail)."
echo ""
echo "📝 YOUR TASK:"
echo "  1. Review the messy notes in 'Discovered Errors' sheet"
echo "  2. Build a structured tracking system in 'Dispute Tracker' sheet"
echo ""
echo "  Required columns:"
echo "    • Bureau Name"
echo "    • Error/Account Description"
echo "    • Account Number (if applicable)"
echo "    • Date Error Discovered"
echo "    • Date Dispute Sent"
echo "    • Certified Mail Tracking Number"
echo "    • 30-Day Response Deadline (FORMULA: =DateSent+30)"
echo "    • Status"
echo "    • Documentation Attached"
echo "    • Notes/Follow-up Needed"
echo ""
echo "  3. Transform all 4 errors into organized rows:"
echo "     ✓ Capital One fraudulent card (Experian)"
echo "     ✓ Navient student loan wrong balance (TransUnion)"
echo "     ✓ Midwest Medical collection already settled (multiple bureaus)"
echo "     ✓ Wrong address (Equifax)"
echo ""
echo "  4. Add realistic certified mail tracking numbers"
echo "     Format: 9999 9999 9999 9999 9999 99 (20-22 digits)"
echo ""
echo "  5. Use formulas to auto-calculate 30-day deadlines"
echo ""
echo "  6. Add status indicators (e.g., 'Pending Response', 'Sent 1/20/25', etc.)"
echo ""
echo "  7. Save the spreadsheet (Ctrl+S)"
echo ""
echo "💡 TIP: The Midwest Medical error appears on ALL THREE bureaus,"
echo "        so you may need separate dispute entries for each bureau."