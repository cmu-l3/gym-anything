#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Crowdfunding Calculator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with guidance structure
SHEET_PATH="$WORKSPACE_DIR/crowdfund_calculator.xlsx"

cat > /tmp/create_crowdfund_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Campaign Calculator"

# Section 1: Reward Tier Design (Rows 1-7)
ws['A1'] = "Tier Name"
ws['B1'] = "Pledge Amount"
ws['C1'] = "Material Cost"
ws['D1'] = "Shipping Cost"
ws['E1'] = "Net Per Backer"

# Make headers bold
for col in ['A1', 'B1', 'C1', 'D1', 'E1']:
    ws[col].font = Font(bold=True)
    ws[col].fill = PatternFill(start_color="CCCCCC", end_color="CCCCCC", fill_type="solid")

# Tier names (pre-filled as guidance)
ws['A2'] = "Digital Thank You"
ws['A3'] = "Bookplate Pack"
ws['A4'] = "Graphic Novel Bundle"
ws['A5'] = "Class Visit + Books"
ws['A6'] = "Full Library Sponsor"

# Add instructions
ws['G1'] = "INSTRUCTIONS:"
ws['G1'].font = Font(bold=True, size=12)
ws['G2'] = "1. Fill in tier pricing and costs (columns B, C, D)"
ws['G3'] = "2. Add formulas in column E for Net Per Backer"
ws['G4'] = "3. Fill in scenario backer counts (section 2)"
ws['G5'] = "4. Create financial summary formulas (section 3)"
ws['G6'] = "5. Save with Ctrl+S"

# Section 2: Scenario Modeling (Rows 9-15)
ws['A9'] = "Tier Name"
ws['B9'] = "Conservative Count"
ws['C9'] = "Optimistic Count"

for col in ['A9', 'B9', 'C9']:
    ws[col].font = Font(bold=True)
    ws[col].fill = PatternFill(start_color="CCCCCC", end_color="CCCCCC", fill_type="solid")

# Tier names for scenarios
ws['A10'] = "Digital Thank You"
ws['A11'] = "Bookplate Pack"
ws['A12'] = "Graphic Novel Bundle"
ws['A13'] = "Class Visit + Books"
ws['A14'] = "Full Library Sponsor"

# Section 3: Financial Summary (Rows 17-27)
ws['A17'] = "Metric"
ws['B17'] = "Conservative"
ws['C17'] = "Optimistic"

for col in ['A17', 'B17', 'C17']:
    ws[col].font = Font(bold=True)
    ws[col].fill = PatternFill(start_color="CCCCCC", end_color="CCCCCC", fill_type="solid")

ws['A18'] = "Gross Funding"
ws['A19'] = "Total Fulfillment Cost"
ws['A20'] = "Net Funding"
ws['A21'] = "Campaign Goal"
ws['A22'] = "Goal Achieved?"
ws['A23'] = "Surplus/Deficit"
ws['A24'] = "Platform Fee (8%)"

# Section 4: Key Insight
ws['A26'] = "After fees and fulfillment, net funding:"
ws['A26'].font = Font(italic=True)

# Set column widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 18
ws.column_dimensions['E'].width = 18
ws.column_dimensions['G'].width = 45

wb.save(sys.argv[1])
print(f"Spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_crowdfund_sheet.py
python3 /tmp/create_crowdfund_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_crowdfund_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_crowdfund_task.log || true
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

echo "=== Crowdfunding Calculator Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: Maya wants to launch a Kickstarter for 'Diverse Voices in Comics' library"
echo "   Campaign Goal: \$2,500 | Budget: \$800 upfront"
echo ""
echo "🎯 YOUR TASK:"
echo ""
echo "SECTION 1: Reward Tier Design (Rows 2-6)"
echo "  Fill in these values for each tier:"
echo "    Digital Thank You:       \$5 pledge  | \$0 material  | \$0 shipping"
echo "    Bookplate Pack:          \$15 pledge | \$3 material  | \$2 shipping"
echo "    Graphic Novel Bundle:    \$40 pledge | \$18 material | \$8 shipping"
echo "    Class Visit + Books:     \$150 pledge| \$50 material | \$12 shipping"
echo "    Full Library Sponsor:    \$500 pledge| \$100 material| \$0 shipping"
echo "  Column E: CREATE FORMULA for Net Per Backer = Pledge - Material - Shipping"
echo ""
echo "SECTION 2: Scenario Modeling (Rows 10-14)"
echo "  Conservative: 20, 15, 8, 2, 1 backers"
echo "  Optimistic:   40, 25, 15, 4, 2 backers"
echo ""
echo "SECTION 3: Financial Summary (Rows 18-24)"
echo "  B18: Gross Funding = SUM(Pledge × Backer Count) for Conservative"
echo "  C18: Same for Optimistic"
echo "  B19: Total Fulfillment Cost = SUM((Material + Shipping) × Count)"
echo "  B20: Net Funding = Gross - Fulfillment"
echo "  B21: Campaign Goal = 2500"
echo "  B22: Goal Achieved? = IF(Net >= Goal, \"YES\", \"NO\")"
echo "  B23: Surplus/Deficit = Net - Goal"
echo "  B24: Platform Fee = 8% of Gross"
echo "  (Repeat for column C)"
echo ""
echo "ROW 27: After-fees calculation = Net Funding - Platform Fee"
echo ""
echo "💡 IMPORTANT: Use FORMULAS, not hardcoded calculations!"
echo "   Expected results: Conservative ~\$1,485 net, Optimistic ~\$3,290 net"
echo ""
echo "💾 SAVE with Ctrl+S when done"