#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Childcare Swap Balancer Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with raw session data
SHEET_PATH="$WORKSPACE_DIR/childcare_swap_raw.xlsx"

cat > /tmp/create_childcare_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()

# Sheet 1: Sessions (raw data)
ws_sessions = wb.active
ws_sessions.title = "Sessions"

# Headers for sessions sheet
headers = ["Date", "WatcherFamily", "ChildFamily", "Hours", "Notes"]
ws_sessions.append(headers)

# Style headers
header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF")
for cell in ws_sessions[1]:
    cell.fill = header_fill
    cell.font = header_font
    cell.alignment = Alignment(horizontal="center")

# Raw babysitting session data (16 sessions over 2 months)
sessions_data = [
    ["2024-01-05", "Miller", "Chen", 3, "Evening movie date"],
    ["2024-01-12", "Chen", "Rodriguez", 4, "Saturday errands"],
    ["2024-01-15", "Rodriguez", "Miller", 2, "Quick appointment"],
    ["2024-01-20", "Patel", "Chen", 3.5, "Work emergency"],
    ["2024-01-27", "Miller", "Patel", 4, "Date night"],
    ["2024-02-03", "Rodriguez", "Chen", 2.5, "Doctor visit"],
    ["2024-02-08", "Chen", "Miller", 3, "Late work shift"],
    ["2024-02-10", "Miller", "Rodriguez", 3.5, "Anniversary dinner"],
    ["2024-02-15", "Patel", "Miller", 2, "Gym session"],
    ["2024-02-18", "Chen", "Patel", 4, "Weekend trip"],
    ["2024-02-22", "Rodriguez", "Patel", 3, "Family event"],
    ["2024-02-25", "Patel", "Rodriguez", 2.5, "Shopping day"],
    ["2024-03-01", "Miller", "Chen", 3, "Concert tickets"],
    ["2024-03-05", "Chen", "Rodriguez", 2, "Haircut appointment"],
    ["2024-03-08", "Rodriguez", "Miller", 4, "Theater show"],
    ["2024-03-12", "Patel", "Chen", 3, "Medical appointment"]
]

for row_data in sessions_data:
    ws_sessions.append(row_data)

# Adjust column widths
ws_sessions.column_dimensions['A'].width = 12
ws_sessions.column_dimensions['B'].width = 15
ws_sessions.column_dimensions['C'].width = 15
ws_sessions.column_dimensions['D'].width = 10
ws_sessions.column_dimensions['E'].width = 25

# Sheet 2: Summary (empty template for agent to fill)
ws_summary = wb.create_sheet("Summary")

# Add title and headers
ws_summary['A1'] = "Family Balance Report"
ws_summary['A1'].font = Font(size=14, bold=True, color="2F5496")

ws_summary['A3'] = "Family"
ws_summary['B3'] = "Hours Given"
ws_summary['C3'] = "Hours Received"
ws_summary['D3'] = "Net Balance"

# Style summary headers
for cell in ['A3', 'B3', 'C3', 'D3']:
    ws_summary[cell].font = Font(bold=True)
    ws_summary[cell].fill = PatternFill(start_color="D9E1F2", end_color="D9E1F2", fill_type="solid")
    ws_summary[cell].alignment = Alignment(horizontal="center")

# Add placeholder rows for families (agent will fill these)
families = ["Miller", "Chen", "Rodriguez", "Patel"]
for i, family in enumerate(families, start=4):
    ws_summary[f'A{i}'] = family

# Add instructions
ws_summary['A9'] = "Instructions:"
ws_summary['A9'].font = Font(bold=True, color="C00000")
ws_summary['A10'] = "1. Calculate Hours Given for each family (use SUMIF on Sessions sheet)"
ws_summary['A11'] = "2. Calculate Hours Received for each family (use SUMIF on Sessions sheet)"
ws_summary['A12'] = "3. Calculate Net Balance = Hours Given - Hours Received"
ws_summary['A13'] = "4. Apply conditional formatting: Red if balance > +3, Orange if < -3"
ws_summary['A14'] = "5. Calculate Maximum Imbalance below"

ws_summary['A16'] = "Maximum Imbalance:"
ws_summary['A16'].font = Font(bold=True)

# Adjust column widths
ws_summary.column_dimensions['A'].width = 20
ws_summary.column_dimensions['B'].width = 15
ws_summary.column_dimensions['C'].width = 18
ws_summary.column_dimensions['D'].width = 15

wb.save(sys.argv[1])
print(f"Childcare swap spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_childcare_sheet.py
python3 /tmp/create_childcare_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_childcare_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_childcare_task.log || true
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

echo "=== Childcare Swap Balancer Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Sheet 'Sessions' contains 16 babysitting sessions for 4 families"
echo "  Sheet 'Summary' needs to be completed with:"
echo "    1. Hours Given by each family (SUMIF formulas)"
echo "    2. Hours Received by each family (SUMIF formulas)"
echo "    3. Net Balance (Given - Received)"
echo "    4. Conditional formatting for imbalances"
echo "    5. Maximum imbalance calculation"
echo ""
echo "Expected totals:"
echo "  Miller: Given 13.5, Received 11, Balance +2.5"
echo "  Chen: Given 13, Received 15, Balance -2"
echo "  Rodriguez: Given 11.5, Received 12, Balance -0.5"
echo "  Patel: Given 11, Received 11, Balance 0"