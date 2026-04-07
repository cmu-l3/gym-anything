#!/bin/bash
echo "=== Setting up nyc_lease_walt_analysis task ==="

# Timestamp for anti-gaming
date +%s > /tmp/task_start_time.txt

FILE_PATH="/home/ga/Documents/nyc_brooklyn_leases.xlsx"
rm -f "$FILE_PATH" 2>/dev/null || true

# Generate realistic NYC lease dataset using python
python3 << 'PYEOF'
import datetime
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = 'Lease Data'

headers = ['Borough', 'Address', 'Agency', 'Square_Footage', 'Lease_Start', 'Lease_End', 'Annual_Rent']
ws.append(headers)

# Realistic data ensuring a mix of expired, near-term (<24mo), and long-term leases relative to 2026-01-01
leases = [
    ['Brooklyn', '100 Gold St', 'HPD', 50000, datetime.datetime(2015,1,1), datetime.datetime(2025,12,31), 2500000],  # Expired (0 mo)
    ['Brooklyn', '350 Jay St', 'ACS', 25000, datetime.datetime(2018,6,1), datetime.datetime(2026,5,31), 1250000],   # Near-term (5 mo)
    ['Brooklyn', '900 Atlantic Ave', 'NYPD', 15000, datetime.datetime(2010,5,1), datetime.datetime(2027,4,30), 600000], # Near-term (16 mo)
    ['Brooklyn', '120 Schermerhorn', 'COURTS', 80000, datetime.datetime(2020,1,1), datetime.datetime(2030,12,31), 4000000], # Long (60 mo)
    ['Brooklyn', '250 Livingston St', 'HRA', 60000, datetime.datetime(2014,3,1), datetime.datetime(2024,2,28), 2100000], # Expired (0 mo)
    ['Brooklyn', '1 Metrotech Center', 'FDNY', 100000, datetime.datetime(2022,7,1), datetime.datetime(2032,6,30), 6500000], # Long (78 mo)
    ['Brooklyn', '400 Adams St', 'DOF', 35000, datetime.datetime(2019,9,1), datetime.datetime(2026,8,31), 1800000], # Near-term (8 mo)
    ['Brooklyn', '150 Court St', 'DOP', 12000, datetime.datetime(2021,2,1), datetime.datetime(2031,1,31), 720000] # Long (61 mo)
]

for l in leases:
    ws.append(l)

# Format headers
header_font = Font(bold=True, color='FFFFFF')
header_fill = PatternFill(start_color='1F4E78', end_color='1F4E78', fill_type='solid')
for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Format Currency (Annual_Rent)
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=7, max_col=7):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Format Dates
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=5, max_col=6):
    for cell in row:
        cell.number_format = 'YYYY-MM-DD'

# Column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 10
ws.column_dimensions['D'].width = 16
ws.column_dimensions['E'].width = 14
ws.column_dimensions['F'].width = 14
ws.column_dimensions['G'].width = 18

wb.save('/home/ga/Documents/nyc_brooklyn_leases.xlsx')
PYEOF

chown ga:ga "$FILE_PATH" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -x "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$FILE_PATH' &"
    
    # Wait for window
    for i in {1..30}; do
        if DISPLAY=:1 wmctrl -l | grep -qi "nyc_brooklyn_leases"; then
            break
        fi
        sleep 1
    done
fi

# Maximize and focus
DISPLAY=:1 wmctrl -r "nyc_brooklyn_leases" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "nyc_brooklyn_leases" 2>/dev/null || true
sleep 2

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="