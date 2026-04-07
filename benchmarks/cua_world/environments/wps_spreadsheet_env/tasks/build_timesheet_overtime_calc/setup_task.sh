#!/bin/bash
echo "=== Setting up build_timesheet_overtime_calc task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Ensure WPS Spreadsheet is closed
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 1

# Generate the initial dataset
cat << 'PYEOF' > /tmp/generate_data.py
#!/usr/bin/env python3
import os
from openpyxl import Workbook
from openpyxl.styles import Font
from datetime import datetime, time

wb = Workbook()

# === Employees Sheet ===
ws_emp = wb.active
ws_emp.title = "Employees"
ws_emp.append(["Employee_ID", "Name", "Department", "Hourly_Rate"])

employees = [
    ("E001", "Maria Santos",     "Assembly",   22.50),
    ("E002", "James O'Brien",    "Assembly",   24.00),
    ("E003", "Lin Wei",          "Assembly",   21.00),
    ("E004", "Priya Sharma",     "Assembly",   23.50),
    ("E005", "Robert Jackson",   "Assembly",   25.00),
    ("E006", "Sarah Mitchell",   "Quality",    26.00),
    ("E007", "Ahmed Hassan",     "Quality",    27.50),
    ("E008", "Jennifer Kim",     "Quality",    24.50),
    ("E009", "Carlos Rodriguez", "Quality",    28.00),
    ("E010", "David Thompson",   "Warehouse",  19.50),
    ("E011", "Anna Kowalski",    "Warehouse",  20.00),
    ("E012", "Michael Brown",    "Warehouse",  18.50),
    ("E013", "Fatima Al-Rashid", "Warehouse",  21.50),
    ("E014", "Thomas Nguyen",    "Warehouse",  19.00),
    ("E015", "Rachel Green",     "Assembly",   22.00),
]
for emp in employees:
    ws_emp.append(list(emp))

for row in range(2, 17):
    ws_emp.cell(row=row, column=4).number_format = '#,##0.00'
for col in range(1, 5):
    ws_emp.cell(row=1, column=col).font = Font(bold=True)
ws_emp.column_dimensions['A'].width = 14
ws_emp.column_dimensions['B'].width = 22
ws_emp.column_dimensions['C'].width = 14
ws_emp.column_dimensions['D'].width = 14

# === Time_Records Sheet ===
ws_tr = wb.create_sheet("Time_Records")
ws_tr.append(["Employee_ID", "Date", "Clock_In", "Clock_Out"])

records = [
    # E001 (some OT)
    ("E001", datetime(2024,11,4),  6, 0, 14,30), ("E001", datetime(2024,11,5),  6, 0, 16, 0), ("E001", datetime(2024,11,6),  6, 0, 14,30), ("E001", datetime(2024,11,7),  6, 0, 14, 0), ("E001", datetime(2024,11,8),  6, 0, 15, 0),
    # E002 (no OT)
    ("E002", datetime(2024,11,4),  6, 0, 14, 0), ("E002", datetime(2024,11,5),  6, 0, 14, 0), ("E002", datetime(2024,11,6),  6, 0, 14, 0), ("E002", datetime(2024,11,7),  6, 0, 14, 0), ("E002", datetime(2024,11,8),  6, 0, 14, 0),
    # E003 (heavy OT)
    ("E003", datetime(2024,11,4),  5,45, 16,15), ("E003", datetime(2024,11,5),  5,45, 16, 0), ("E003", datetime(2024,11,6),  6, 0, 16,30), ("E003", datetime(2024,11,7),  5,45, 16, 0), ("E003", datetime(2024,11,8),  6, 0, 14, 0),
    # E004 (short Friday)
    ("E004", datetime(2024,11,4),  6, 0, 14,30), ("E004", datetime(2024,11,5),  6, 0, 14, 0), ("E004", datetime(2024,11,6),  6, 0, 14,30), ("E004", datetime(2024,11,7),  6, 0, 14, 0), ("E004", datetime(2024,11,8),  6, 0, 10, 0),
    # E005
    ("E005", datetime(2024,11,4),  6, 0, 15, 0), ("E005", datetime(2024,11,5),  6, 0, 15,30), ("E005", datetime(2024,11,6),  6, 0, 15, 0), ("E005", datetime(2024,11,7),  6, 0, 16, 0), ("E005", datetime(2024,11,8),  6, 0, 15, 0),
    # E006
    ("E006", datetime(2024,11,4),  7, 0, 15,30), ("E006", datetime(2024,11,5),  7, 0, 15, 0), ("E006", datetime(2024,11,6),  7, 0, 15, 0), ("E006", datetime(2024,11,7),  7, 0, 15,30), ("E006", datetime(2024,11,8),  7, 0, 15, 0),
    # E007
    ("E007", datetime(2024,11,4),  7, 0, 17, 0), ("E007", datetime(2024,11,5),  7, 0, 17, 0), ("E007", datetime(2024,11,6),  7, 0, 15, 0), ("E007", datetime(2024,11,7),  7, 0, 17, 0), ("E007", datetime(2024,11,8),  7, 0, 16, 0),
    # E008
    ("E008", datetime(2024,11,4),  7, 0, 15, 0), ("E008", datetime(2024,11,5),  7, 0, 15, 0), ("E008", datetime(2024,11,6),  7, 0, 15, 0), ("E008", datetime(2024,11,7),  7, 0, 15, 0), ("E008", datetime(2024,11,8),  7, 0, 12, 0),
    # E009
    ("E009", datetime(2024,11,4),  7, 0, 16,30), ("E009", datetime(2024,11,5),  7, 0, 16, 0), ("E009", datetime(2024,11,6),  7, 0, 16,30), ("E009", datetime(2024,11,7),  7, 0, 16, 0), ("E009", datetime(2024,11,8),  7, 0, 16,30),
    # E010
    ("E010", datetime(2024,11,4),  8, 0, 16, 0), ("E010", datetime(2024,11,5),  8, 0, 16,30), ("E010", datetime(2024,11,6),  8, 0, 16, 0), ("E010", datetime(2024,11,7),  8, 0, 16,30), ("E010", datetime(2024,11,8),  8, 0, 16, 0),
    # E011
    ("E011", datetime(2024,11,4),  8, 0, 18, 0), ("E011", datetime(2024,11,5),  8, 0, 18, 0), ("E011", datetime(2024,11,6),  8, 0, 16, 0), ("E011", datetime(2024,11,7),  8, 0, 18, 0), ("E011", datetime(2024,11,8),  8, 0, 18, 0),
    # E012
    ("E012", datetime(2024,11,4),  8, 0, 16, 0), ("E012", datetime(2024,11,5),  8, 0, 16, 0), ("E012", datetime(2024,11,6),  8, 0, 16, 0), ("E012", datetime(2024,11,7),  8, 0, 16, 0), ("E012", datetime(2024,11,8),  8, 0, 16, 0),
    # E013
    ("E013", datetime(2024,11,4),  8, 0, 17, 0), ("E013", datetime(2024,11,5),  8, 0, 16, 0), ("E013", datetime(2024,11,6),  8, 0, 17,30), ("E013", datetime(2024,11,7),  8, 0, 16, 0), ("E013", datetime(2024,11,8),  8, 0, 17, 0),
    # E014
    ("E014", datetime(2024,11,4),  8, 0, 16,30), ("E014", datetime(2024,11,5),  8, 0, 16,30), ("E014", datetime(2024,11,6),  8, 0, 16,30), ("E014", datetime(2024,11,7),  8, 0, 16,30), ("E014", datetime(2024,11,8),  8, 0, 16,30),
    # E015
    ("E015", datetime(2024,11,4),  6, 0, 14, 0), ("E015", datetime(2024,11,5),  6, 0, 15, 0), ("E015", datetime(2024,11,6),  6, 0, 14, 0), ("E015", datetime(2024,11,7),  6, 0, 15,30), ("E015", datetime(2024,11,8),  6, 0, 14, 0),
]

for rec in records:
    ws_tr.append([rec[0], rec[1], time(rec[2], rec[3]), time(rec[4], rec[5])])

for row in range(2, 77):
    ws_tr.cell(row=row, column=2).number_format = 'YYYY-MM-DD'
    ws_tr.cell(row=row, column=3).number_format = 'h:mm AM/PM'
    ws_tr.cell(row=row, column=4).number_format = 'h:mm AM/PM'

for col in range(1, 5):
    ws_tr.cell(row=1, column=col).font = Font(bold=True)

ws_tr.column_dimensions['A'].width = 14
ws_tr.column_dimensions['B'].width = 14
ws_tr.column_dimensions['C'].width = 14
ws_tr.column_dimensions['D'].width = 14

output_path = "/home/ga/Documents/time_clock_data.xlsx"
os.makedirs(os.path.dirname(output_path), exist_ok=True)
wb.save(output_path)
PYEOF

# Run python script to generate data
python3 /tmp/generate_data.py
chown ga:ga /home/ga/Documents/time_clock_data.xlsx

# Record initial file modification time to prevent gaming
stat -c %Y /home/ga/Documents/time_clock_data.xlsx > /tmp/initial_mtime.txt

# Start WPS Spreadsheet as ga user
echo "Starting WPS Spreadsheet..."
su - ga -c "DISPLAY=:1 et /home/ga/Documents/time_clock_data.xlsx &"

# Wait for WPS Window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Spreadsheets"; then
        echo "WPS Window detected"
        break
    fi
    sleep 1
done

# Dismiss any popup dialogs
sleep 2
DISPLAY=:1 wmctrl -c "System Check" 2>/dev/null || true
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Maximize Window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Take Initial Screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="