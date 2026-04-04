#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Freelance Time Reconciliation Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the time logs reference file (messy format - realistic!)
TIME_LOGS_PATH="$WORKSPACE_DIR/time_logs.txt"

cat > "$TIME_LOGS_PATH" << 'EOF'
FREELANCE TIME LOGS - DECEMBER 2024
====================================

Notes: This is a mess! Need to consolidate for invoicing by Dec 31.
GreenLeaf has a $1,200 budget cap - watch out for overages!

WEEK 1 (Dec 4-7):
------------------
Dec 4 - TechStart website redesign (TS-WEB) - 3.5 hrs @ $85/hr
Dec 5 - GreenLeaf logo concepts (GL-LOGO) - 5 hrs @ $75/hr
Dec 6 - TechStart website (TS-WEB) continued - 2.5 hrs @ $85/hr
Dec 7 - MarketPro social media graphics (MP-SM) - 4 hrs @ $70/hr

WEEK 2 (Dec 11-14):
-------------------
Dec 11: GreenLeaf logo revisions (GL-LOGO) - 3 hours, $75/hr
Dec 12: TechStart website (TS-WEB) - 4 hours, $85/hr
Dec 13: GreenLeaf brand guidelines (GL-BRAND) - 2.5 hours, $75/hr
Dec 14: MarketPro social media (MP-SM) - 3.5 hours, $70/hr

WEEK 3 (Dec 18-20):
-------------------
12/18 - TechStart website revisions (TS-WEB), 3 hrs, $85/hr
12/19 - GreenLeaf brand guidelines (GL-BRAND), 4 hrs, $75/hr
12/20 - MarketPro email templates (MP-EMAIL), 5 hrs, $70/hr

WEEK 4 (Dec 23-27):
-------------------
Dec 23: GreenLeaf Co - brand guidelines (GL-BRAND) - 3 hours @ $75/hr
Dec 26: TechStart - final review (TS-WEB) - 1.5 hours @ $85/hr
Dec 27: MarketPro - presentation deck (MP-PRES) - 4 hours @ $70/hr

TOTALS NEEDED:
- Total hours worked
- Total amount to invoice
- Per-client breakdowns (TechStart, GreenLeaf Co, MarketPro)
- Flag if any client exceeded their budget!

CLIENT RATES:
- TechStart: $85/hr
- GreenLeaf Co: $75/hr (BUDGET CAP: $1,200)
- MarketPro: $70/hr
EOF

chown ga:ga "$TIME_LOGS_PATH"
echo "✅ Time logs created at: $TIME_LOGS_PATH"

# Create the initial spreadsheet with column headers
SHEET_PATH="$WORKSPACE_DIR/freelance_timesheet_dec.xlsx"

cat > /tmp/create_timesheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "December Timesheet"

# Add title
ws['A1'] = "FREELANCE TIME TRACKING - DECEMBER 2024"
ws['A1'].font = Font(size=14, bold=True)
ws.merge_cells('A1:G1')

# Add instruction
ws['A2'] = "Reference time_logs.txt for entries. Create formulas for calculations."
ws['A2'].font = Font(size=10, italic=True)
ws.merge_cells('A2:G2')

# Add column headers
headers = ["Date", "Client Name", "Project Code", "Hours Worked", "Hourly Rate", "Amount", "Notes"]
for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=4, column=col_idx)
    cell.value = header
    cell.font = Font(bold=True)
    cell.fill = PatternFill(start_color="DDDDDD", end_color="DDDDDD", fill_type="solid")
    cell.alignment = Alignment(horizontal="center")

# Add some spacing rows for data entry (rows 5-20 for entries)

# Add section for totals (starting at row 22)
ws['A22'] = "TOTALS:"
ws['A22'].font = Font(size=12, bold=True)

ws['A23'] = "Total Hours:"
ws['A23'].font = Font(bold=True)

ws['A24'] = "Total Amount:"
ws['A24'].font = Font(bold=True)

# Add section for client summaries (starting at row 26)
ws['A26'] = "CLIENT SUMMARIES:"
ws['A26'].font = Font(size=12, bold=True)

ws['A27'] = "TechStart - Total Hours:"
ws['A28'] = "TechStart - Total Amount:"

ws['A30'] = "GreenLeaf Co - Total Hours:"
ws['A31'] = "GreenLeaf Co - Total Amount:"
ws['A32'] = "GreenLeaf Co - Budget Status:"
ws['A32'].font = Font(italic=True)

ws['A34'] = "MarketPro - Total Hours:"
ws['A35'] = "MarketPro - Total Amount:"

# Set column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 14
ws.column_dimensions['E'].width = 13
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 20

wb.save(sys.argv[1])
print(f"Timesheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_timesheet.py
python3 /tmp/create_timesheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Timesheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_freelance_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_freelance_task.log || true
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

# Open the time logs file in a text editor for reference
echo "Opening time logs reference file..."
su - ga -c "DISPLAY=:1 xdg-open '$TIME_LOGS_PATH' > /dev/null 2>&1 &" || true
sleep 2

echo "=== Freelance Time Reconciliation Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Reference time_logs.txt (opened in text editor)"
echo "  2. Enter all 14 time entries into the spreadsheet"
echo "  3. Use columns: Date | Client Name | Project Code | Hours | Rate | Amount | Notes"
echo "  4. Create formulas in Amount column (Hours × Rate)"
echo "  5. Calculate total hours worked (should be ~47.5)"
echo "  6. Calculate total amount to invoice (should be ~$3,685)"
echo "  7. Create per-client summaries:"
echo "     - TechStart: hours + amount"
echo "     - GreenLeaf Co: hours + amount (note $1,200 budget cap!)"
echo "     - MarketPro: hours + amount"
echo "  8. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Total: ~47.5 hours, ~$3,685"
echo "  - TechStart: ~14.5 hrs, ~$1,232.50"
echo "  - GreenLeaf: ~17.5 hrs, ~$1,312.50 (EXCEEDS $1,200 BUDGET!)"
echo "  - MarketPro: ~16.5 hrs, ~$1,155"