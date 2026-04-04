#!/bin/bash
echo "=== Setting up compensation_equity_analysis task ==="

OUTPUT_FILE="/home/ga/Documents/compensation_equity_review.xlsx"

rm -f "$OUTPUT_FILE" 2>/dev/null || true
rm -f /tmp/compensation_equity_result.json 2>/dev/null || true
rm -f /tmp/compensation_equity_gt.json 2>/dev/null || true

date +%s > /tmp/compensation_equity_start_ts

# Data sources:
# - Salary data: Calibrated to BLS Occupational Employment and Wage Statistics (OEWS),
#   May 2024 release. Median wages: Software Developers $133,080; Financial Analysts
#   $101,350; HR Specialists $72,910; HR Managers $140,030; Marketing Managers $161,030.
#   Source: https://www.bls.gov/oes/2024/may/
# - Market benchmarks: BLS OEWS May 2024 percentile wage estimates (25th/50th/75th/90th)
#   by occupation. Source: https://www.bls.gov/oes/tables.htm

python3 << 'PYEOF'
import csv
import json
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment, Border, Side
from datetime import datetime

wb = Workbook()

header_font = Font(bold=True, size=11, color='FFFFFF')
header_fill = PatternFill(start_color='7030A0', end_color='7030A0', fill_type='solid')
section_fill = PatternFill(start_color='E2D1F0', end_color='E2D1F0', fill_type='solid')

# === Sheet 1: Employees ===
ws = wb.active
ws.title = 'Employees'
ws['A1'] = 'Employee Compensation Data - Annual Review 2025'
ws['A1'].font = Font(bold=True, size=14, color='7030A0')
ws.merge_cells('A1:J1')

emp_headers = ['Emp ID', 'Name', 'Title', 'Job Level', 'Department', 'Hire Date',
               'Annual Salary', 'Gender', 'Ethnicity', 'Performance Rating']
for col, h in enumerate(emp_headers, 1):
    cell = ws.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

with open('/workspace/data/employee_compensation.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        ws.cell(row=i, column=1, value=row['Emp_ID'])
        ws.cell(row=i, column=2, value=row['Name'])
        ws.cell(row=i, column=3, value=row['Title'])
        ws.cell(row=i, column=4, value=row['Job_Level'])
        ws.cell(row=i, column=5, value=row['Department'])
        ws.cell(row=i, column=6, value=datetime.strptime(row['Hire_Date'], '%Y-%m-%d'))
        ws.cell(row=i, column=6).number_format = 'YYYY-MM-DD'
        ws.cell(row=i, column=7, value=int(row['Annual_Salary']))
        ws.cell(row=i, column=7).number_format = '$#,##0'
        ws.cell(row=i, column=8, value=row['Gender'])
        ws.cell(row=i, column=9, value=row['Ethnicity'])
        ws.cell(row=i, column=10, value=row['Performance_Rating'])

for col_idx, width in enumerate([10, 22, 26, 10, 18, 12, 14, 9, 12, 16], 1):
    ws.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

# === Sheet 2: Market Benchmarks ===
ws2 = wb.create_sheet(title='Market_Benchmarks')
ws2['A1'] = 'Market Salary Benchmarks - 2025 Industry Survey'
ws2['A1'].font = Font(bold=True, size=14, color='7030A0')
ws2.merge_cells('A1:F1')

bench_headers = ['Job Family', 'Job Level', 'Market 25th', 'Market 50th (Midpoint)', 'Market 75th', 'Market 90th']
for col, h in enumerate(bench_headers, 1):
    cell = ws2.cell(row=3, column=col, value=h)
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center', wrap_text=True)

with open('/workspace/data/market_benchmarks.csv', 'r') as f:
    reader = csv.DictReader(f)
    for i, row in enumerate(reader, 4):
        ws2.cell(row=i, column=1, value=row['Job_Family'])
        ws2.cell(row=i, column=2, value=row['Job_Level'])
        for col, key in enumerate(['Market_25th', 'Market_50th', 'Market_75th', 'Market_90th'], 3):
            cell = ws2.cell(row=i, column=col, value=int(row[key]))
            cell.number_format = '$#,##0'

for col_idx, width in enumerate([22, 10, 14, 20, 14, 14], 1):
    ws2.column_dimensions[openpyxl.utils.get_column_letter(col_idx)].width = width

wb.save('/home/ga/Documents/compensation_equity_review.xlsx')
print(f"Created compensation workbook with sheets: {wb.sheetnames}")

# Save ground truth
gt = {
    "total_employees": 36,
    "gender_count_f": 18,
    "gender_count_m": 18,
    "starter_sheets": ["Employees", "Market_Benchmarks"],
    "benchmark_rows": 24
}
with open('/tmp/compensation_equity_gt.json', 'w') as f:
    json.dump(gt, f)

PYEOF

chown ga:ga "$OUTPUT_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the file (pre-positioning principle)
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$OUTPUT_FILE' &"

# Wait for WPS window to appear
for i in $(seq 1 30); do
    if DISPLAY=:1 wmctrl -l 2>/dev/null | grep -qi "\.xlsx\|WPS Spreadsheets\|et"; then
        echo "WPS Spreadsheet window is ready"
        break
    fi
    sleep 2
done

# Take initial screenshot
sleep 2
DISPLAY=:1 import -window root /tmp/compensation_equity_start_screenshot.png 2>/dev/null || \
    DISPLAY=:1 scrot /tmp/compensation_equity_start_screenshot.png 2>/dev/null || true

echo "=== Task setup complete ==="
