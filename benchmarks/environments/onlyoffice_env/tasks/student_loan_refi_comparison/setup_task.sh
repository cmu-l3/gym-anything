#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Student Loan Refinancing Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the loan information text file
LOAN_INFO_PATH="$WORKSPACE_DIR/loan_info.txt"

cat > "$LOAN_INFO_PATH" << 'LOANEOF'
CURRENT STUDENT LOANS (6 total):

Federal Loan 1: $12,500 balance, 4.5% interest, 8 years remaining, $156/month
Federal Loan 2: $8,200 balance, 5.05% interest, 8 years remaining, $104/month  
Federal Loan 3: $15,800 balance, 3.76% interest, 10 years remaining, $159/month
Private Loan 1: $9,100 balance, 7.2% interest, 7 years remaining, $139/month
Private Loan 2: $6,500 balance, 6.8% interest, 6 years remaining, $108/month
Federal Loan 4: $11,200 balance, 4.29% interest, 9 years remaining, $135/month

TOTAL CURRENT: $63,300 balance, $801/month combined payment

===============================================

REFINANCING OFFERS RECEIVED:

Offer A (CredibleBank):
- Combines all 6 loans: $63,300 total balance
- Interest rate: 5.25% fixed
- Term: 10 years
- Monthly payment: $679
- Origination fee: $0
- Marketing claim: "Save $122/month!"

Offer B (SoFi):  
- Combines all 6 loans: $63,300 total balance
- Interest rate: 4.75% fixed
- Term: 8 years
- Monthly payment: $764
- Origination fee: 2% of loan amount ($1,266)
- Marketing claim: "Lowest rate! Save thousands!"

Offer C (CommonBond):
- Combines all 6 loans: $63,300 total balance  
- Interest rate: 4.99% fixed
- Term: 12 years
- Monthly payment: $588
- Origination fee: 1% of loan amount ($633)
- Marketing claim: "Lowest monthly payment - save $213/month!"

===============================================

IMPORTANT NOTES:
- Refinancing federal loans means losing income-driven repayment options
- Refinancing federal loans means losing public service loan forgiveness eligibility
- Refinancing federal loans means losing deferment/forbearance protections
- Consider total cost over life of loan, not just monthly payment
- Factor in origination fees when calculating total cost

TASK: Create a spreadsheet to compare these options and make an informed decision.
LOANEOF

chown ga:ga "$LOAN_INFO_PATH"
echo "✅ Loan information file created at: $LOAN_INFO_PATH"

# Create a starter spreadsheet with 3 blank sheets (to guide structure)
SHEET_PATH="$WORKSPACE_DIR/refi_comparison.xlsx"

cat > /tmp/create_refi_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()

# Remove default sheet and create our 3 sheets
if 'Sheet' in wb.sheetnames:
    wb.remove(wb['Sheet'])

# Sheet 1: Current Loans Analysis
ws1 = wb.create_sheet("Current Loans Analysis", 0)
ws1['A1'] = "Loan Name"
ws1['B1'] = "Balance"
ws1['C1'] = "Interest Rate"
ws1['D1'] = "Years Remaining"
ws1['E1'] = "Monthly Payment"
ws1['F1'] = "Total Interest Paid"

# Format headers
header_font = Font(bold=True)
for col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']:
    ws1[col].font = header_font

# Add instruction note
ws1['A3'] = "↓ Enter your 6 current loans below ↓"
ws1['A3'].font = Font(italic=True, color="666666")

# Sheet 2: Refinancing Offers
ws2 = wb.create_sheet("Refinancing Offers", 1)
ws2['A1'] = "Offer Name"
ws2['B1'] = "Total Balance"
ws2['C1'] = "Interest Rate"
ws2['D1'] = "Term (Years)"
ws2['E1'] = "Monthly Payment"
ws2['F1'] = "Origination Fee"
ws2['G1'] = "Total Cost Over Life"

# Format headers
for col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1', 'G1']:
    ws2[col].font = header_font

# Add instruction note
ws2['A3'] = "↓ Enter 3 refinancing offers below ↓"
ws2['A3'].font = Font(italic=True, color="666666")

# Sheet 3: Decision Matrix
ws3 = wb.create_sheet("Decision Matrix", 2)
ws3['A1'] = "Option"
ws3['B1'] = "Monthly Payment"
ws3['C1'] = "Total Interest + Fees"
ws3['D1'] = "Cash Flow Change"
ws3['E1'] = "Total Savings"
ws3['F1'] = "Years to Payoff"
ws3['G1'] = "Federal Protection?"

# Format headers
for col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1', 'G1']:
    ws3[col].font = header_font

# Add instruction note
ws3['A3'] = "↓ Compare current situation vs 3 offers ↓"
ws3['A3'].font = Font(italic=True, color="666666")

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_refi_sheet.py
python3 /tmp/create_refi_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_refi_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_refi_task.log || true
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

echo "=== Student Loan Refinancing Comparison Task Setup Complete ==="
echo ""
echo "📋 SCENARIO:"
echo "  You graduated 2 years ago and have 6 student loans with different servicers."
echo "  You've received 3 refinancing offers promising savings."
echo "  You need to analyze ALL the numbers to make an informed decision."
echo ""
echo "📄 REFERENCE FILE: $LOAN_INFO_PATH"
echo "  Read this file for all loan details and refinancing offer information."
echo ""
echo "📝 YOUR TASK:"
echo "  Create a comprehensive comparison spreadsheet with 3 sheets:"
echo ""
echo "  Sheet 1: 'Current Loans Analysis'"
echo "    - Enter all 6 loans with: balance, interest rate, years remaining, monthly payment"
echo "    - Calculate 'Total Interest Paid' for each: (Monthly Payment × 12 × Years) - Balance"
echo "    - Add a summary row with SUM formulas for: total balance, combined monthly payment, total interest"
echo ""
echo "  Sheet 2: 'Refinancing Offers'"
echo "    - Enter all 3 offers with: balance, rate, term, monthly payment, origination fee"
echo "    - Calculate 'Total Cost Over Life': (Monthly Payment × 12 × Term) + Origination Fee"
echo "    - Add comparison row showing savings vs current loans"
echo ""
echo "  Sheet 3: 'Decision Matrix'"
echo "    - Create comparison table with 4 rows: Current + Offer A + Offer B + Offer C"
echo "    - Columns: Monthly Payment, Total Interest+Fees, Cash Flow Change, Total Savings, Years, Federal Protection"
echo "    - Add note about losing federal protections"
echo ""
echo "  FORMATTING:"
echo "    - Apply bold formatting to all headers"
echo "    - Format money values as currency ($)"
echo "    - Use formulas for calculations (not hardcoded numbers)"
echo ""
echo "  💾 Save the spreadsheet when complete (Ctrl+S)"
echo ""
echo "🧮 EXPECTED INSIGHTS:"
echo "  - Current situation: ~$76,500 total cost over remaining life"
echo "  - Offer A: Lower monthly but longer term = similar total cost"
echo "  - Offer B: Highest monthly but shortest term = lowest total cost (~$73,000)"
echo "  - Offer C: Lowest monthly but longest term = highest total cost"
echo "  - Trade-off: Federal protections vs interest savings"