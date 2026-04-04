#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Financial Aid Dispute Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the financial aid dispute tracker spreadsheet
SHEET_PATH="$WORKSPACE_DIR/financial_aid_dispute.xlsx"

cat > /tmp/create_aid_tracker.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Remove default sheet
if 'Sheet' in wb.sheetnames:
    wb.remove(wb['Sheet'])

# ============================================================================
# Sheet 1: EFC Calculation Comparison
# ============================================================================
ws1 = wb.create_sheet("EFC Calculation Comparison", 0)

# Headers
ws1['A1'] = "Aid Office Calculation (INCORRECT)"
ws1['A1'].font = Font(bold=True)
ws1['A1'].alignment = Alignment(horizontal='center')

ws1['D1'] = "Correct Calculation (Federal Formula)"
ws1['D1'].font = Font(bold=True)
ws1['D1'].alignment = Alignment(horizontal='center')

# Original (Incorrect) Calculation
ws1['A3'] = "Parent AGI:"
ws1['B3'] = "$68,000"
ws1['A4'] = "Student Income:"
ws1['B4'] = "$4,200"
ws1['A5'] = "Assets:"
ws1['B5'] = "$8,500"
ws1['A6'] = "Household Size:"
ws1['B6'] = 4
ws1['A7'] = "Students in College:"
ws1['B7'] = 1
ws1['B7'].font = Font(italic=True, color="FF0000")  # Red to indicate error
ws1['A8'] = "Calculated EFC:"
ws1['B8'] = "$12,400"

# Corrected Calculation
ws1['D3'] = "Parent AGI:"
ws1['E3'] = "$68,000"
ws1['D4'] = "Student Income:"
ws1['E4'] = "$4,200"
ws1['D5'] = "Assets:"
ws1['E5'] = "$8,500"
ws1['D6'] = "Household Size:"
ws1['E6'] = 4
ws1['D7'] = "Students in College:"
ws1['E7'] = 2
ws1['E7'].font = Font(italic=True, color="00B050")  # Green to indicate correct
ws1['D8'] = "Calculated EFC:"
ws1['E8'] = "$10,000"

ws1['D9'] = "DISCREPANCY:"
ws1['E9'] = "$2,400"
# User needs to make this BOLD and RED

# Set column widths
ws1.column_dimensions['A'].width = 20
ws1.column_dimensions['B'].width = 15
ws1.column_dimensions['D'].width = 25
ws1.column_dimensions['E'].width = 15

# ============================================================================
# Sheet 2: Communication Log
# ============================================================================
ws2 = wb.create_sheet("Communication Log", 1)

# Headers
headers2 = ["Date", "Time", "Staff Name", "Department/Position", "Method", "Issue Discussed", "Response/Action", "Follow-up Needed"]
for col_idx, header in enumerate(headers2, start=1):
    cell = ws2.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D9D9D9", end_color="D9D9D9", fill_type="solid")

# Data rows
data2 = [
    ["1/8/2025", "2:15 PM", "Jennifer Martinez", "Front Desk Advisor", "In-person", "Reported EFC error", "Said to email documents", "YES"],
    ["1/10/2025", "10:30 AM", "(No name given)", "Phone Representative", "Phone", "Asked what documents needed", "Said 'just send everything'", "YES"],
    ["1/13/2025", "3:45 PM", "Robert Chen", "Senior Counselor", "Email", "Explained sibling enrollment", "Requested sibling's enrollment verification", "IN PROGRESS"],
    ["1/15/2025", "9:00 AM", "Jennifer Martinez", "Front Desk Advisor", "In-person", "Submitted verification form", "Said '2-3 weeks processing time' - UNACCEPTABLE", "ESCALATE"]
]

for row_idx, row_data in enumerate(data2, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws2.cell(row=row_idx, column=col_idx, value=value)

# Set column widths
for col_idx in range(1, 9):
    ws2.column_dimensions[chr(64 + col_idx)].width = 18

# ============================================================================
# Sheet 3: Document Tracker
# ============================================================================
ws3 = wb.create_sheet("Document Tracker", 2)

# Headers
headers3 = ["Document Name", "Submission Date", "Submission Method", "Confirmation Number", "Received By", "Status"]
for col_idx, header in enumerate(headers3, start=1):
    cell = ws3.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)

# Data rows
data3 = [
    ["FAFSA Confirmation (2 students)", "1/10/2025", "Email attachment", "Email confirmation saved", "Robert Chen", "SUBMITTED"],
    ["Sibling Enrollment Verification", "1/13/2025", "In-person dropoff", "Stamped copy received", "Front desk", "CONFIRMED"],
    ["Federal EFC Formula Documentation", "1/13/2025", "Email attachment", "Email timestamp", "Robert Chen", "SUBMITTED"],
    ["Parent Income Verification (W-2)", "1/15/2025", "Online portal", "Portal receipt #8847392", "System auto-confirm", "PENDING REVIEW"]
]

for row_idx, row_data in enumerate(data3, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws3.cell(row=row_idx, column=col_idx, value=value)

# Set column widths
for col_idx in range(1, 7):
    ws3.column_dimensions[chr(64 + col_idx)].width = 22

# ============================================================================
# Sheet 4: Financial Impact Scenarios
# ============================================================================
ws4 = wb.create_sheet("Financial Impact Scenarios", 3)

ws4['A1'] = "Scenario Analysis: Financial Impact"
ws4['A1'].font = Font(bold=True, size=14, underline="single")

ws4['A3'] = "Original Aid Package:"
ws4['B3'] = 18500
ws4['B3'].number_format = '$#,##0'

ws4['A4'] = "Corrected Aid Package (if approved):"
# User needs to create formula: =B3+2400
ws4['B4'].number_format = '$#,##0'

ws4['A5'] = "Spring Tuition Due:"
ws4['B5'] = 22000
ws4['B5'].number_format = '$#,##0'

ws4['A7'] = "Scenario 1: Dispute Resolved Before Deadline"
ws4['A7'].font = Font(bold=True)

ws4['A8'] = "  Out-of-pocket cost:"
# User needs to create formula: =B5-B4
ws4['B8'].number_format = '$#,##0'

ws4['A10'] = "Scenario 2: Dispute NOT Resolved, Late Fee Applied"
ws4['A10'].font = Font(bold=True)

ws4['A11'] = "  Out-of-pocket cost:"
# User needs to create formula: =(B5-B3)+150
ws4['B11'].number_format = '$#,##0'

ws4['A13'] = "Difference Between Scenarios:"
ws4['A13'].font = Font(bold=True)
# User needs to create formula: =B11-B8
ws4['B13'].number_format = '$#,##0'

ws4.column_dimensions['A'].width = 40
ws4.column_dimensions['B'].width = 20

# ============================================================================
# Sheet 5: Deadline Tracker
# ============================================================================
ws5 = wb.create_sheet("Deadline Tracker", 4)

# Headers
headers5 = ["Deadline Item", "Date", "Days Remaining", "Critical?", "Notes"]
for col_idx, header in enumerate(headers5, start=1):
    cell = ws5.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)

# Data rows
data5 = [
    ["Tuition Payment Due", "1/27/2025", 19, "YES", "$150 late fee if missed"],
    ["Financial Aid Office 'Normal Processing'", "2/3/2025", 26, "NO", "Their quoted timeline - UNACCEPTABLE"],
    ["Add/Drop Deadline", "2/10/2025", 33, "YES", "Last day to drop classes without penalty"],
    ["Federal Aid Disbursement Cutoff", "2/15/2025", 38, "YES", "After this, spring aid cannot be adjusted"]
]

for row_idx, row_data in enumerate(data5, start=2):
    for col_idx, value in enumerate(row_data, start=1):
        ws5.cell(row=row_idx, column=col_idx, value=value)

# Set column widths
ws5.column_dimensions['A'].width = 35
ws5.column_dimensions['B'].width = 15
ws5.column_dimensions['C'].width = 18
ws5.column_dimensions['D'].width = 12
ws5.column_dimensions['E'].width = 40

# Save workbook
wb.save(sys.argv[1])
print(f"Financial aid dispute tracker created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_aid_tracker.py
python3 /tmp/create_aid_tracker.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Financial aid dispute tracker created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_aid_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_aid_task.log || true
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

echo "=== Financial Aid Dispute Tracker Task Setup Complete ==="
echo ""
echo "📝 SCENARIO: You discovered a \$2,400 financial aid error. The aid office"
echo "   incorrectly calculated your EFC by not accounting for your sibling's"
echo "   concurrent college enrollment. You have 19 days until tuition deadline."
echo ""
echo "📋 YOUR TASKS:"
echo ""
echo "Sheet 1 - EFC Calculation Comparison:"
echo "  • Highlight row 7 (Students in College) in YELLOW background"
echo "  • Format cell E9 (discrepancy amount) in BOLD and RED text"
echo ""
echo "Sheet 2 - Communication Log:"
echo "  • Color code column H (Follow-up Needed):"
echo "    - 'YES' → RED background"
echo "    - 'IN PROGRESS' → YELLOW background"
echo "    - 'ESCALATE' → DARK RED background"
echo ""
echo "Sheet 3 - Document Tracker:"
echo "  • Color code column F (Status) text colors:"
echo "    - 'CONFIRMED' → GREEN text"
echo "    - 'SUBMITTED' → BLUE text"
echo "    - 'PENDING REVIEW' → ORANGE text"
echo ""
echo "Sheet 4 - Financial Impact Scenarios:"
echo "  • Cell B4: Create formula =B3+2400"
echo "  • Cell B8: Create formula =B5-B4"
echo "  • Cell B11: Create formula =(B5-B3)+150"
echo "  • Cell B13: Create formula =B11-B8"
echo "  • Format B13 in BOLD, RED text, and size 14pt"
echo ""
echo "Sheet 5 - Deadline Tracker:"
echo "  • Apply background colors to column C (Days Remaining):"
echo "    - Less than 20 → RED background"
echo "    - 20-30 → YELLOW background"
echo "    - Over 30 → GREEN background"
echo "  • Format 'YES' in column D (Critical?) in BOLD RED"
echo ""
echo "💾 Save the spreadsheet (Ctrl+S) when complete!"
echo ""