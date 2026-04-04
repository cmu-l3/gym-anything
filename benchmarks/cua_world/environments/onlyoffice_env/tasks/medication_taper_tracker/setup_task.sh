#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Medication Taper Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with taper schedule data
SHEET_PATH="$WORKSPACE_DIR/prednisone_taper_raw.xlsx"

cat > /tmp/create_taper_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Taper Schedule"

# Headers (Row 1)
ws['A1'] = 'Day'
ws['B1'] = 'Target Dose (mg)'
ws['C1'] = 'Pills to Take'
ws['D1'] = 'Cumulative Pills Used'
ws['E1'] = 'Pills Remaining'
ws['F1'] = 'Symptoms / Side Effects'

# Make headers bold
for col in ['A1', 'B1', 'C1', 'D1', 'E1', 'F1']:
    ws[col].font = Font(bold=True)
    ws[col].alignment = Alignment(horizontal='left')

# Add note about starting supply
ws['H1'] = 'Starting Supply:'
ws['I1'] = 120
ws['H1'].font = Font(bold=True)

# 28-day realistic prednisone taper schedule
# Days 1-3: 20mg
# Days 4-7: 17.5mg
# Days 8-11: 15mg
# Days 12-15: 12.5mg
# Days 16-19: 10mg
# Days 20-22: 7.5mg
# Days 23-25: 5mg
# Days 26-28: 2.5mg

schedule = (
    [20]*3 + [17.5]*4 + [15]*4 + [12.5]*4 + 
    [10]*4 + [7.5]*3 + [5]*3 + [2.5]*3
)

# Fill in day numbers and target doses
for i, dose in enumerate(schedule, start=2):
    ws[f'A{i}'] = i - 1  # Day number (1-28)
    ws[f'B{i}'] = dose   # Target dose in mg

# Add placeholders for agent to fill
ws['C2'] = '[Formula: =B2/5]'
ws['D2'] = '[Formula: =C2]'
ws['E2'] = '[Formula: =$I$1-D2]'

# Add instructions in cells below the data
ws['A30'] = '↓ Add Summary Calculations Below ↓'
ws['A30'].font = Font(italic=True, color='808080')

# Set column widths
ws.column_dimensions['A'].width = 8
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 22
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 25
ws.column_dimensions['H'].width = 15
ws.column_dimensions['I'].width = 12

wb.save(sys.argv[1])
print(f"✓ Taper schedule spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_taper_sheet.py
python3 /tmp/create_taper_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_taper_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_taper_task.log || true
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

echo "=== Medication Taper Tracker Task Setup Complete ==="
echo ""
echo "📋 TASK CONTEXT:"
echo "   You are tapering off prednisone after 14 months of treatment."
echo "   Your doctor provided a 28-day tapering schedule with decreasing doses."
echo "   You have 120 tablets of 5mg prednisone in your current prescription."
echo ""
echo "📝 INSTRUCTIONS:"
echo "   Column C - Pills to Take:"
echo "     • In C2, enter formula: =B2/5"
echo "     • Copy formula down to C29 (all 28 days)"
echo ""
echo "   Column D - Cumulative Pills Used:"
echo "     • In D2, enter formula: =C2"
echo "     • In D3, enter formula: =D2+C3"
echo "     • Copy D3 formula down to D29"
echo ""
echo "   Column E - Pills Remaining:"
echo "     • In E2, enter formula: =\$I\$1-D2"
echo "     • Copy formula down to E29"
echo ""
echo "   Column F - Already has header 'Symptoms / Side Effects'"
echo ""
echo "   Summary Section (rows 31-33):"
echo "     • A31: 'Total Pills Needed'  |  B31: =SUM(C2:C29)"
echo "     • A32: 'Pills Remaining After Taper'  |  B32: =I1-B31"
echo "     • A33: 'Taper Status'  |  B33: =IF(B32>=0,\"✓ Sufficient Supply\",\"⚠ REFILL NEEDED\")"
echo ""
echo "   Then save the spreadsheet (Ctrl+S)"
echo ""
echo "💊 EXPECTED RESULTS:"
echo "   - Total Pills Needed: ~124.5"
echo "   - Pills Remaining: ~-4.5 (negative = need refill)"
echo "   - Status: '⚠ REFILL NEEDED'"