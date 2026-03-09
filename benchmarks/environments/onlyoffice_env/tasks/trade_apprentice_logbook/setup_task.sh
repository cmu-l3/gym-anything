#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Trade Apprentice Logbook Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with partial data
SHEET_PATH="$WORKSPACE_DIR/apprentice_hours_draft.xlsx"

cat > /tmp/create_apprentice_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys
from datetime import datetime

wb = Workbook()
ws = wb.active
ws.title = "Hours Log"

# Column headers (row 1)
ws['A1'] = "Date"
ws['B1'] = "Hours Worked"
ws['C1'] = "Supervision"
ws['D1'] = "Work Type"
ws['E1'] = "Notes"

# Make headers bold
for col in ['A1', 'B1', 'C1', 'D1', 'E1']:
    ws[col].font = Font(bold=True)

# Work entry data - 15 entries, some incomplete
# Format: [date, hours, supervision, work_type, notes]
work_entries = [
    ["2024-01-15", 35.0, "Supervised", "Residential", "Week 1 - New construction wiring"],
    ["2024-01-22", 28.5, "Supervised", "Residential", "Week 2 - Panel installations"],
    ["2024-01-29", 37.0, "Supervised", "Commercial", "Week 3 - Office building lighting"],
    ["2024-02-05", 30.5, "Supervised", None, "Week 4 - office building 3rd floor (comm.)"],  # Missing work type
    ["2024-02-12", 24.0, "Supervised", "Industrial", "Week 5 - Factory equipment install"],
    ["2024-02-19", 40.0, "Supervised", "Commercial", "Week 6 - Retail store remodel"],
    ["2024-02-26", 26.0, "Supervised", "Service/Repair", "Week 7 - Emergency service calls"],
    ["2024-03-04", 25.0, None, "Service/Repair", "Week 8 - solo service calls, no super"],  # Missing supervision
    ["2024-03-11", 29.0, "Supervised", "Residential", "Week 9 - Kitchen rewiring projects"],
    ["2024-03-18", 33.0, "Supervised", "Commercial", "Week 10 - Restaurant upgrade"],
    ["2024-03-25", 31.5, "Supervised", "Industrial", "Week 11 - Warehouse lighting"],
    ["2024-04-01", None, "Supervised", "Residential", "Week 12 - whole house rewire (9.5h noted)"],  # Missing hours
    ["2024-04-08", 28.0, "Independent", "Service/Repair", "Week 13 - Independent troubleshooting"],
    ["2024-04-15", 29.0, "Supervised", "Commercial", "Week 14 - Bank branch update"],
    ["2024-04-22", 24.5, "Supervised", "Residential", "Week 15 - Outdoor lighting install"],
]

# Add work entries starting from row 2
for i, entry in enumerate(work_entries, start=2):
    ws[f'A{i}'] = entry[0]
    if entry[1] is not None:  # Hours
        ws[f'B{i}'] = entry[1]
    if entry[2] is not None:  # Supervision
        ws[f'C{i}'] = entry[2]
    if entry[3] is not None:  # Work type
        ws[f'D{i}'] = entry[3]
    ws[f'E{i}'] = entry[4]  # Notes

# Add summary section labels (starting at row 18)
ws['A18'] = "Total Supervised:"
ws['A19'] = "Total Independent:"
ws['A20'] = "Grand Total:"
ws['A21'] = "Remaining to 8000:"
ws['A22'] = "Progress:"

# Add work type breakdown labels
ws['D18'] = "Residential:"
ws['D19'] = "Commercial:"
ws['D20'] = "Industrial:"
ws['D21'] = "Service/Repair:"

# Make summary labels bold
for cell in ['A18', 'A19', 'A20', 'A21', 'A22', 'D18', 'D19', 'D20', 'D21']:
    ws[cell].font = Font(bold=True)

# Add placeholder text for formulas (these will be replaced by the user)
ws['B18'] = "[Add SUMIF formula for supervised hours]"
ws['B19'] = "[Add SUMIF formula for independent hours]"
ws['B20'] = "[Add formula for total]"
ws['B21'] = "[Add formula: 8000 - total]"
ws['B22'] = "[Add percentage formula]"

ws['E18'] = "[Add SUMIF for Residential]"
ws['E19'] = "[Add SUMIF for Commercial]"
ws['E20'] = "[Add SUMIF for Industrial]"
ws['E21'] = "[Add SUMIF for Service/Repair]"

# Adjust column widths for readability
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 14
ws.column_dimensions['C'].width = 14
ws.column_dimensions['D'].width = 16
ws.column_dimensions['E'].width = 40

wb.save(sys.argv[1])
print(f"✅ Apprentice logbook draft created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_apprentice_sheet.py
python3 /tmp/create_apprentice_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_apprentice_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_apprentice_task.log || true
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

echo "=== Trade Apprentice Logbook Task Setup Complete ==="
echo ""
echo "📋 SCENARIO: You're an electrical apprentice who needs to document"
echo "   work hours for state licensing (8,000 hours required)."
echo ""
echo "📝 TASKS:"
echo "   PART 1 - Fix incomplete entries:"
echo "     • Row 5 (cell D5): Add missing work type 'Commercial'"
echo "     • Row 9 (cell C9): Add missing supervision 'Independent'"
echo "     • Row 13 (cell B13): Add missing hours '9.5'"
echo ""
echo "   PART 2 - Create formulas in summary section:"
echo "     • B18: Total supervised hours =SUMIF(C2:C16,\"Supervised\",B2:B16)"
echo "     • B19: Total independent hours =SUMIF(C2:C16,\"Independent\",B2:B16)"
echo "     • B20: Grand total =B18+B19"
echo "     • B21: Hours remaining =8000-B20"
echo "     • B22: Progress % =B20/8000 (format as percentage)"
echo ""
echo "   PART 3 - Work type breakdown formulas:"
echo "     • E18: =SUMIF(D2:D16,\"Residential\",B2:B16)"
echo "     • E19: =SUMIF(D2:D16,\"Commercial\",B2:B16)"
echo "     • E20: =SUMIF(D2:D16,\"Industrial\",B2:B16)"
echo "     • E21: =SUMIF(D2:D16,\"Service/Repair\",B2:B16)"
echo ""
echo "   PART 4 - Professional formatting:"
echo "     • Insert row at top, merge A1:E1"
echo "     • Add title: 'Electrical Apprenticeship Hour Log - 2024'"
echo "     • Make title bold, 14pt"
echo "     • Add apprentice ID 'EA-2847-TX' somewhere visible"
echo ""
echo "   PART 5 - Conditional formatting (BONUS):"
echo "     • B19: Red background if value >1600"
echo "     • B22: Green if ≥50%, yellow/orange if <50%"
echo ""
echo "   PART 6 - Save with Ctrl+S"
echo ""
echo "Expected results after completion:"
echo "   • Supervised: ~378 hours"
echo "   • Independent: ~53 hours"
echo "   • Total: ~431 hours"
echo "   • Remaining: ~7569 hours"
echo "   • Progress: ~5.4%"