#!/bin/bash
echo "=== Setting up clean_municipal_payroll task ==="

# Timestamp for anti-gaming verification
date +%s > /tmp/task_start_time.txt

TARGET_FILE="/home/ga/Documents/chicago_employees.xlsx"
rm -f "$TARGET_FILE" 2>/dev/null || true

# Generate the messy real-world equivalent data subset
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws = wb.active
ws.title = 'Employees'

headers = ["Name", "Job Titles", "Department", "Full or Part-Time", "Salary or Hourly", "Typical Hours", "Annual Salary", "Hourly Rate"]
ws.append(headers)

base_data = [
    ["AARON,  KARINA", "POLICE OFFICER", "POLICE", "F", "Salary", None, 90024.00, None],
    ["ABBATACOLA,  ROBERT J", "ELECTRICAL MECHANIC", "AVIATION", "F", "Hourly", 40, None, 50.50],
    ["ABBOTT,  LYNISE M", "POOL MOTOR TRUCK DRIVER", "STREETS & SAN", "F", "Hourly", 40, None, 35.60],
    ["ABDALLAH,  ZAID", "POLICE OFFICER", "POLICE", "F", "Salary", None, 84054.00, None],
    ["ABDELHADI,  ABDALMAHD", "POLICE OFFICER", "POLICE", "F", "Salary", None, 87006.00, None],
    ["ABDELLATIF,  AREF R", "FIREFIGHTER/PARAMEDIC", "FIRE", "F", "Salary", None, 102228.00, None],
    ["ABDELMAJEID,  AZIZ", "POLICE OFFICER", "POLICE", "F", "Salary", None, 84054.00, None],
    ["ABDULLAH,  DANIEL N", "FIREFIGHTER-EMT", "FIRE", "F", "Salary", None, 95484.00, None],
    ["ABDULLAH,  LAKENYA N", "CROSSING GUARD", "POLICE", "P", "Hourly", 20, None, 19.38],
    ["ABRAHAM,  GIRLEY T", "CIVIL ENGINEER IV", "WATER MGMNT", "F", "Salary", None, 116784.00, None],
    ["ABRAMAVICIUS,  ANNA A", "SUPERVISING TRAFFIC CHANNELIZER", "AVIATION", "F", "Salary", None, 60840.00, None],
    ["ABRAMS,  DANIELLE T", "SANITATION LABORER", "STREETS & SAN", "F", "Hourly", 40, None, 38.35],
    ["ABRAMS,  JOSHUA D", "POLICE OFFICER", "POLICE", "F", "Salary", None, 90024.00, None],
    ["ABRAMS,  RHONDA L", "DIR OF OPERATIONS", "WATER MGMNT", "F", "Salary", None, 112008.00, None],
    ["ABRON,  FLOYD", "CONSTRUCTION LABORER", "WATER MGMNT", "F", "Hourly", 40, None, 43.12],
    ["ACEVEDO,  AARON F", "POLICE OFFICER", "POLICE", "F", "Salary", None, 87006.00, None],
    ["ACEVEDO,  EDWARD J", "MACHINIST (AUTOMOTIVE)", "AVIATION", "F", "Hourly", 40, None, 49.34],
    ["ACEVEDO,  MARTIN", "SANITATION LABORER", "STREETS & SAN", "F", "Hourly", 40, None, 38.35],
    ["ACRE,  ANTHONY", "FIREFIGHTER-EMT", "FIRE", "F", "Salary", None, 95484.00, None],
    ["ADAMS,  JAMES", "HOISTING ENGINEER", "STREETS & SAN", "F", "Hourly", 40, None, 53.10],
    ["ADAMS,  JERRY", "MOTOR TRUCK DRIVER", "WATER MGMNT", "F", "Hourly", 40, None, 39.50],
    ["ADAMS,  RICHARD", "FIREFIGHTER-EMT", "FIRE", "F", "Salary", None, 98000.00, None],
    ["ADKINS,  WILLIAM", "POLICE OFFICER", "POLICE", "F", "Salary", None, 92000.00, None],
    ["AGUIRRE,  CARLOS", "AVIATION SECURITY OFFICER", "AVIATION", "F", "Salary", None, 75000.00, None],
    ["ALEXANDER,  MICHAEL", "SANITATION LABORER", "STREETS & SAN", "F", "Hourly", 40, None, 38.35]
]

data = base_data + [[row[0] + " JR", row[1], row[2], row[3], row[4], row[5], row[6], row[7]] for row in base_data]

for row in data:
    ws.append(row)

header_font = Font(bold=True)
header_fill = PatternFill(start_color='D3D3D3', end_color='D3D3D3', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill

ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 30
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 15
ws.column_dimensions['F'].width = 15
ws.column_dimensions['G'].width = 15
ws.column_dimensions['H'].width = 15

wb.save('/home/ga/Documents/chicago_employees.xlsx')
PYEOF

chown ga:ga "$TARGET_FILE" 2>/dev/null || true

# Pre-launch WPS Spreadsheets
if ! pgrep -f "et " > /dev/null; then
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/chicago_employees.xlsx &"
    sleep 5
fi

# Wait for window to stabilize
for i in {1..15}; do
    if DISPLAY=:1 wmctrl -l | grep -qi "chicago_employees"; then
        break
    fi
    sleep 1
done

# Maximize and focus application
DISPLAY=:1 wmctrl -r "chicago_employees" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "chicago_employees" 2>/dev/null || true
sleep 1

# Take initial state screenshot for trajectory verification
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Setup complete ==="