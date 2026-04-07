#!/bin/bash
echo "=== Setting up audit_benfords_law_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/vendor_payments_FY23.xlsx"

# Remove any existing file
rm -f "$DATA_FILE" 2>/dev/null || true

# Generate realistic municipal vendor payment data (8,500 records)
# Amounts are distributed log-uniformly to naturally obey Benford's Law,
# with seeded anomalies (e.g. Health dept invoice splitting) to trigger the flag.
python3 << 'PYEOF'
import openpyxl
import random
from datetime import datetime, timedelta

random.seed(42)

wb = openpyxl.Workbook()
ws = wb.active
ws.title = "Payments"

headers = ["Payment_ID", "Date", "Vendor_Name", "Department", "Amount"]
ws.append(headers)

vendors = ["GovTech Solutions", "Citywide Maintenance", "Apex Office Supplies", 
           "Global Infrastructure", "Metro Transit Authority", "United Health Care", 
           "Local Builders Inc.", "Pioneer Energy"]
depts = ["Public Works", "Education", "Health & Human Services", 
         "Transportation", "Parks & Rec", "Police", "Fire"]

for i in range(1, 8501):
    pid = f"INV-23-{i:05d}"
    date = (datetime(2023, 1, 1) + timedelta(days=random.randint(0, 364))).strftime("%Y-%m-%d")
    vendor = random.choice(vendors)
    dept = random.choice(depts)
    
    # Benford-distributed base amounts: 10^U(1, 5)
    amt = round(10 ** random.uniform(1.0, 5.2), 2)
    
    # Inject anomaly: Health Dept splits invoices to avoid $10k review thresholds (~$8k range)
    # This creates an artificial spike in leading digit '8'
    if dept == "Health & Human Services" and random.random() < 0.18:
        amt = round(random.uniform(8000, 8999), 2)
        
    ws.append([pid, date, vendor, dept, amt])

# Formatting
from openpyxl.styles import Font, PatternFill, Alignment
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color="366092", end_color="366092", fill_type="solid")

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal="center")

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=5, max_col=5):
    for cell in row:
        cell.number_format = '$#,##0.00'

ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 25
ws.column_dimensions['D'].width = 25
ws.column_dimensions['E'].width = 15

wb.save('/home/ga/Documents/vendor_payments_FY23.xlsx')
print(f"Created {ws.max_row - 1} records simulating municipal vendor payments.")
PYEOF

# Ensure proper permissions
chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$DATA_FILE' &"
    sleep 8
fi

# Maximize and focus window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "vendor_payments_FY23.xlsx" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
DISPLAY=:1 wmctrl -a "vendor_payments_FY23.xlsx" 2>/dev/null || true

# Take initial state screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="