#!/bin/bash
set -e
echo "=== Setting up build_loan_amortization task ==="

# Record task start time for anti-gaming checks
date +%s > /tmp/task_start_time.txt

# Target file path
LOAN_FILE="/home/ga/Documents/loan_amortization.xlsx"

# Remove existing file if present
rm -f "$LOAN_FILE" 2>/dev/null || true

# Generate the initial spreadsheet template programmatically
python3 << 'PYEOF'
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill, Border, Side
from datetime import datetime

wb = Workbook()
ws = wb.active
ws.title = "Amortization"

# Title
ws['A1'] = "Commercial Equipment Loan - Amortization Schedule"
ws['A1'].font = Font(bold=True, size=14)
ws.merge_cells('A1:H1')

# Loan Parameters section
ws['A3'] = "Loan Parameters"
ws['A3'].font = Font(bold=True, size=12, underline='single')

param_font = Font(bold=True)
parameters = [
    ("Borrower:", "Meridian Manufacturing LLC", None),
    ("Lender:", "First National Business Bank", None),
    ("Loan Purpose:", "CNC Milling Equipment Purchase", None),
    ("Loan Amount:", 485000, '$#,##0.00'),
    ("Annual Interest Rate:", 0.0725, '0.00%'),
    ("Loan Term (months):", 60, None),
    ("Start Date:", datetime(2024, 1, 15), 'YYYY-MM-DD'),
    ("Payment Frequency:", "Monthly", None)
]

for i, (label, val, fmt) in enumerate(parameters):
    row = i + 4
    ws[f'A{row}'] = label
    ws[f'A{row}'].font = param_font
    ws[f'B{row}'] = val
    if fmt:
        ws[f'B{row}'].number_format = fmt

# Set column widths
widths = {'A': 18, 'B': 24, 'C': 20, 'D': 18, 'E': 18, 'F': 18, 'G': 20, 'H': 20}
for col, width in widths.items():
    ws.column_dimensions[col].width = width

# Table Header
ws['A18'] = "Amortization Schedule"
ws['A18'].font = Font(bold=True, size=12, underline='single')

headers = ["Month #", "Payment Date", "Beginning Balance", "Monthly Payment", 
           "Interest Portion", "Principal Portion", "Ending Balance", "Cumulative Interest"]

header_fill = PatternFill(start_color="4472C4", end_color="4472C4", fill_type="solid")
header_font = Font(bold=True, color="FFFFFF", size=11)
thin_border = Border(left=Side(style='thin'), right=Side(style='thin'), 
                     top=Side(style='thin'), bottom=Side(style='thin'))

for i, header in enumerate(headers, 1):
    cell = ws.cell(row=19, column=i, value=header)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)
    cell.border = thin_border

# Save file (Row 20 onwards left empty for the agent)
wb.save('/home/ga/Documents/loan_amortization.xlsx')
PYEOF

# Ensure proper ownership
chown ga:ga "$LOAN_FILE"
chmod 644 "$LOAN_FILE"

# Record file hash before agent modifications
md5sum "$LOAN_FILE" | awk '{print $1}' > /tmp/initial_file_hash.txt

# Close existing WPS processes
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Launch WPS Spreadsheet with the specific file
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$LOAN_FILE' &"
sleep 6

# Dismiss start/system check dialogs
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
SYSCHECK_WIN=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" | grep -i "System Check" | awk '{print $1}' || echo "")
if [ -n "$SYSCHECK_WIN" ]; then
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -c 'System Check'" 2>/dev/null || true
fi

# Maximize WPS window
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -r ':ACTIVE:' -b add,maximized_vert,maximized_horz" 2>/dev/null || true
sleep 1

# Capture initial screenshot
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; scrot /tmp/task_initial_state.png" 2>/dev/null || true

echo "=== Setup complete ==="