#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Home Office Audit Response Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet template
SHEET_PATH="$WORKSPACE_DIR/audit_response_template.xlsx"

cat > /tmp/create_audit_template.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Remove default sheet and create our three sheets
if 'Sheet' in wb.sheetnames:
    wb.remove(wb['Sheet'])

# Sheet 1: Space_Calculations
ws_space = wb.create_sheet("Space_Calculations", 0)
ws_space['A1'] = "IRS Home Office Audit Response - Space Calculations"
ws_space['A1'].font = Font(bold=True, size=14)

ws_space['A3'] = "Location"
ws_space['B3'] = "Office Sq Ft"
ws_space['C3'] = "Total Home Sq Ft"
ws_space['D3'] = "Business %"
ws_space['E3'] = "Months in 2022"

# Make header row bold
for cell in ws_space[3]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Add row labels
ws_space['A4'] = "Old Apt (Jan-May)"
ws_space['A5'] = "New House (Jun-Dec)"

# Add instruction comments
ws_space['A7'] = "INSTRUCTIONS:"
ws_space['A7'].font = Font(bold=True, color="FF0000")
ws_space['A8'] = "1. Enter office square footage for each residence in column B"
ws_space['A9'] = "2. Enter total home square footage in column C"
ws_space['A10'] = "3. Create formulas in column D: =B4/C4 (calculate percentage)"
ws_space['A11'] = "4. Enter number of months occupied in column E"
ws_space['A12'] = ""
ws_space['A13'] = "Expected values:"
ws_space['A14'] = "  Old Apt: 120 sq ft office / 850 sq ft total = 14.1%"
ws_space['A15'] = "  New House: 180 sq ft office / 1200 sq ft total = 15.0%"

# Set column widths
ws_space.column_dimensions['A'].width = 25
ws_space.column_dimensions['B'].width = 15
ws_space.column_dimensions['C'].width = 18
ws_space.column_dimensions['D'].width = 15
ws_space.column_dimensions['E'].width = 18

# Sheet 2: Monthly_Allocation
ws_monthly = wb.create_sheet("Monthly_Allocation", 1)
ws_monthly['A1'] = "IRS Home Office Audit Response - Monthly Expense Allocation"
ws_monthly['A1'].font = Font(bold=True, size=14)

# Old Apartment section
ws_monthly['A3'] = "OLD APARTMENT (January - May 2022)"
ws_monthly['A3'].font = Font(bold=True, size=12)
ws_monthly['A3'].fill = PatternFill(start_color="FFE699", end_color="FFE699", fill_type="solid")

ws_monthly['A5'] = "Expense Type"
ws_monthly['B5'] = "Monthly Total"
ws_monthly['C5'] = "Business %"
ws_monthly['D5'] = "Business Amount"

for cell in ws_monthly[5]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

ws_monthly['A6'] = "Rent"
ws_monthly['A7'] = "Electricity"
ws_monthly['A8'] = "Internet"
ws_monthly['A9'] = "Renter's Insurance"
ws_monthly['A10'] = "TOTAL per month"
ws_monthly['A10'].font = Font(bold=True)
ws_monthly['A11'] = "Total for 5 months"
ws_monthly['A11'].font = Font(bold=True)

# New House section
ws_monthly['A14'] = "NEW HOUSE (June - December 2022)"
ws_monthly['A14'].font = Font(bold=True, size=12)
ws_monthly['A14'].fill = PatternFill(start_color="C6E0B4", end_color="C6E0B4", fill_type="solid")

ws_monthly['A16'] = "Expense Type"
ws_monthly['B16'] = "Monthly Total"
ws_monthly['C16'] = "Business %"
ws_monthly['D16'] = "Business Amount"

for cell in ws_monthly[16]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

ws_monthly['A17'] = "Rent"
ws_monthly['A18'] = "Electricity"
ws_monthly['A19'] = "Internet"
ws_monthly['A20'] = "Renter's Insurance"
ws_monthly['A21'] = "TOTAL per month"
ws_monthly['A21'].font = Font(bold=True)
ws_monthly['A22'] = "Total for 7 months"
ws_monthly['A22'].font = Font(bold=True)

# Instructions
ws_monthly['A25'] = "INSTRUCTIONS:"
ws_monthly['A25'].font = Font(bold=True, color="FF0000")
ws_monthly['A26'] = "1. Enter monthly expense totals in column B"
ws_monthly['A27'] = "2. In column C, reference business % from Space_Calculations sheet"
ws_monthly['A28'] = "   Example: =Space_Calculations!D4 (for Old Apt)"
ws_monthly['A29'] = "3. For Internet, use 100% business use (1.0 or 100%)"
ws_monthly['A30'] = "4. In column D, calculate: =B6*C6 (Monthly Total × Business %)"
ws_monthly['A31'] = "5. Create SUM formulas for TOTAL per month rows"
ws_monthly['A32'] = "6. Multiply monthly total by number of months for period totals"
ws_monthly['A33'] = ""
ws_monthly['A34'] = "Expense values to use:"
ws_monthly['A35'] = "Old Apt: Rent=$1,650, Electric=$85, Internet=$65, Insurance=$18"
ws_monthly['A36'] = "New House: Rent=$2,100, Electric=$120, Internet=$75, Insurance=$22"

# Set column widths
ws_monthly.column_dimensions['A'].width = 25
ws_monthly.column_dimensions['B'].width = 15
ws_monthly.column_dimensions['C'].width = 15
ws_monthly.column_dimensions['D'].width = 18

# Sheet 3: Annual_Summary
ws_summary = wb.create_sheet("Annual_Summary", 2)
ws_summary['A1'] = "IRS Home Office Audit Response - Annual Summary"
ws_summary['A1'].font = Font(bold=True, size=14)

ws_summary['A3'] = "Period"
ws_summary['B3'] = "Months"
ws_summary['C3'] = "Monthly Average"
ws_summary['D3'] = "Total Claimed"

for cell in ws_summary[3]:
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

ws_summary['A4'] = "Jan-May (Old Apt)"
ws_summary['A5'] = "Jun-Dec (New House)"
ws_summary['A6'] = "ANNUAL TOTAL"
ws_summary['A6'].font = Font(bold=True, size=12)
ws_summary['A6'].fill = PatternFill(start_color="FFC000", end_color="FFC000", fill_type="solid")

# Instructions
ws_summary['A9'] = "INSTRUCTIONS:"
ws_summary['A9'].font = Font(bold=True, color="FF0000")
ws_summary['A10'] = "1. Enter months (5 and 7) in column B"
ws_summary['A11'] = "2. In column C, reference the 'TOTAL per month' from Monthly_Allocation"
ws_summary['A12'] = "   Example: =Monthly_Allocation!D10"
ws_summary['A13'] = "3. In column D, multiply: =C4*B4 (Monthly Avg × Months)"
ws_summary['A14'] = "4. In D6, create SUM formula: =SUM(D4:D5)"
ws_summary['A15'] = ""
ws_summary['A16'] = "CRITICAL: Annual Total must be between $3,550 and $3,650"
ws_summary['A16'].font = Font(bold=True, color="FF0000")
ws_summary['A17'] = "(The IRS is verifying your claimed $3,600 deduction)"

# Set column widths
ws_summary.column_dimensions['A'].width = 25
ws_summary.column_dimensions['B'].width = 12
ws_summary.column_dimensions['C'].width = 18
ws_summary.column_dimensions['D'].width = 15

wb.save(sys.argv[1])
print(f"Audit response template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_audit_template.py
python3 /tmp/create_audit_template.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Audit response template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_audit_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_audit_task.log || true
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

echo "=== Home Office Audit Response Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You received an IRS audit letter requesting documentation"
echo "   for your $3,600 home office deduction. You moved apartments in June"
echo "   2022, so you need to show calculations for BOTH residences."
echo ""
echo "📝 TASK STEPS:"
echo "  1. Fill in Space_Calculations sheet with square footage data"
echo "     - Old Apt: 120 sq ft office, 850 sq ft total"
echo "     - New House: 180 sq ft office, 1200 sq ft total"
echo "     - Create formulas to calculate Business % (office/total)"
echo ""
echo "  2. Fill in Monthly_Allocation sheet with two expense tables"
echo "     - Enter monthly expense amounts (see instructions in sheet)"
echo "     - Reference Business % from Space_Calculations sheet"
echo "     - Internet is 100% business (not prorated)"
echo "     - Create SUM formulas for totals"
echo ""
echo "  3. Fill in Annual_Summary sheet"
echo "     - Reference monthly totals from Monthly_Allocation"
echo "     - Calculate period totals (5 months + 7 months)"
echo "     - Sum to get annual total"
echo ""
echo "  4. Save the spreadsheet (Ctrl+S)"
echo ""
echo "🎯 CRITICAL: Annual total must be $3,550-$3,650 (matching your claimed $3,600)"
echo ""