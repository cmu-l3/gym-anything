#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Student Loan Strategy Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the loan notes text file
NOTES_PATH="$WORKSPACE_DIR/loan_notes.txt"

cat > "$NOTES_PATH" << 'EOF'
Loan Data - Need to organize this!!

Federal Loan 1 (Great Lakes)
Balance: $12,500
Interest Rate: 4.5%
Min Payment: $140/month

Federal Loan 2 (Navient)  
Balance: $18,200
Interest Rate: 5.8%
Min Payment: $195/month

Private Loan 1 (Discover)
Balance: $8,300
Interest Rate: 7.2%
Min Payment: $110/month

Private Loan 2 (SoFi)
Balance: $6,000
Interest Rate: 3.9%
Min Payment: $85/month

TOTAL: $45,000
Total Min Payment: $530/month
Extra money available: $200/month
Total monthly payment: $730

Need to compare:
1. Snowball - pay smallest balance first (Loan 4 -> Loan 3 -> Loan 1 -> Loan 2)
2. Avalanche - pay highest interest first (Loan 3 -> Loan 2 -> Loan 1 -> Loan 4)  
3. Current approach - just split the $200 evenly across all 4 loans ($50 extra each)

Which saves the most money? Which is fastest payoff?
EOF

chown ga:ga "$NOTES_PATH"

echo "✅ Loan notes created at: $NOTES_PATH"

# Create a starter spreadsheet with basic structure (optional - could also start blank)
SHEET_PATH="$WORKSPACE_DIR/loan_comparison.xlsx"

cat > /tmp/create_loan_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Loan Comparison"

# Add a helpful header
ws['A1'] = "Student Loan Payoff Strategy Comparison"
ws['A1'].font = Font(size=14, bold=True)

# Add instruction text
ws['A3'] = "Instructions: Organize the loan data from loan_notes.txt and compare repayment strategies"
ws['A3'].font = Font(size=10, italic=True)

# Leave space for user to work
ws['A5'] = "Loan Summary:"
ws['A5'].font = Font(bold=True)

ws['A15'] = "Strategy Comparison:"
ws['A15'].font = Font(bold=True)

wb.save(sys.argv[1])
print(f"Starter spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_loan_sheet.py
python3 /tmp/create_loan_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Starter spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_loan_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_loan_task.log || true
    # Don't exit - task can still potentially work
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
    # Don't exit - task can still potentially work
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Student Loan Strategy Comparison Task Setup Complete ==="
echo ""
echo "📝 TASK INSTRUCTIONS:"
echo "======================================================================"
echo "You have 4 student loans totaling \$45,000. You have \$200/month extra"
echo "to put toward loans beyond the \$530 minimum payments."
echo ""
echo "GOAL: Create a comparison spreadsheet to decide which repayment"
echo "strategy saves the most money."
echo ""
echo "REQUIRED ELEMENTS:"
echo "  1. Loan Summary Table:"
echo "     - List all 4 loans with: Balance, Interest Rate, Min Payment"
echo "     - Include totals row"
echo ""
echo "  2. Strategy Comparison Table:"
echo "     - Compare 3 strategies: Snowball, Avalanche, Current/Even"
echo "     - Show: Total Interest Paid, Months to Payoff, Total Amount Paid"
echo ""
echo "  3. Use FORMULAS (not just typed numbers)"
echo "     - At least SUM for totals"
echo "     - Calculations for interest/payoff (can be simplified)"
echo ""
echo "  4. Professional Formatting:"
echo "     - Currency formatting (\$) on dollar amounts"
echo "     - Percentage formatting (%) on interest rates"
echo "     - Bold headers"
echo ""
echo "DATA SOURCE: Check loan_notes.txt in the Spreadsheets folder"
echo ""
echo "SAVE AS: loan_comparison.xlsx (already opened)"
echo ""
echo "TIP: Avalanche method (highest interest first) should show"
echo "     lower total interest than other methods."
echo "======================================================================"