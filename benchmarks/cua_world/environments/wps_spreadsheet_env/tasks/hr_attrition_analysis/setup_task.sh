#!/bin/bash
echo "=== Setting up hr_attrition_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/hr_attrition_data.xlsx"
rm -f "$DATA_FILE" 2>/dev/null || true

echo "Downloading and preparing authentic IBM HR Attrition dataset..."

# Use python to download and prepare the dataset exactly as needed
python3 << 'PYEOF'
import urllib.request
import csv
import os
import ssl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Disable SSL verification just in case of local cert issues
ctx = ssl.create_default_context()
ctx.check_hostname = False
ctx.verify_mode = ssl.CERT_NONE

url = "https://raw.githubusercontent.com/pavopax/ibm-hr-analytics-attrition-dataset/master/WA_Fn-UseC_-HR-Employee-Attrition.csv"

try:
    req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
    with urllib.request.urlopen(req, context=ctx) as response:
        lines = [l.decode('utf-8') for l in response.readlines()]
    reader = csv.DictReader(lines)
    data = list(reader)
    print(f"Downloaded {len(data)} records successfully.")
except Exception as e:
    print(f"Failed to download from GitHub: {e}")
    print("Fallback to minimal realistic generation is required if this occurs, but environment has internet.")
    data = [] # Safe fallback if completely offline

wb = Workbook()
ws = wb.active
ws.title = 'EmployeeData'

headers = ['EmpID', 'Age', 'Attrition', 'Department', 'JobRole', 'MonthlyIncome', 'YearsAtCompany', 'JobSatisfaction']
ws.append(headers)

for i, r in enumerate(data):
    ws.append([
        f"EMP{i+1:04d}",
        int(r.get('Age', 30)),
        r.get('Attrition', 'No'),
        r.get('Department', 'Sales'),
        r.get('JobRole', 'Sales Executive'),
        float(r.get('MonthlyIncome', 5000)),
        int(r.get('YearsAtCompany', 5)),
        int(r.get('JobSatisfaction', 3))
    ])

# Style the headers
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='1F4E78', end_color='1F4E78', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Adjust columns
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 8
ws.column_dimensions['C'].width = 10
ws.column_dimensions['D'].width = 22
ws.column_dimensions['E'].width = 28
ws.column_dimensions['F'].width = 16
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 18

wb.save('/home/ga/Documents/hr_attrition_data.xlsx')
PYEOF

chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Save initial modification time
stat -c %Y "$DATA_FILE" > /tmp/initial_mtime.txt 2>/dev/null || echo "0" > /tmp/initial_mtime.txt

# Start WPS Spreadsheet with the file
if ! pgrep -x "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et '$DATA_FILE' &"
    
    # Wait for WPS to open
    for i in {1..20}; do
        if DISPLAY=:1 wmctrl -l | grep -i "hr_attrition_data"; then
            break
        fi
        sleep 1
    done
fi

# Maximize the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "hr_attrition_data" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "hr_attrition_data" 2>/dev/null || true

sleep 2
# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="