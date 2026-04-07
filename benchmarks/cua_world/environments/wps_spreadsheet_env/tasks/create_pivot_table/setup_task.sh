#!/bin/bash
echo "=== Setting up create_pivot_table task ==="

EMPLOYEE_FILE="/home/ga/Documents/employee_sales.xlsx"

rm -f "$EMPLOYEE_FILE" 2>/dev/null || true

# Create employee sales spreadsheet from real data (derived from Kaggle Superstore Sales dataset)
python3 << 'PYEOF'
import csv
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Read real employee/regional sales data from mounted CSV
csv_path = '/workspace/data/employee_sales.csv'
rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

wb = Workbook()
ws = wb.active
ws.title = 'Sales Data'

headers = ['Employee Name', 'Department', 'Region', 'Product', 'Q1 Sales', 'Q2 Sales', 'Q3 Sales', 'Q4 Sales', 'Total Sales']
ws.append(headers)

for r in rows:
    ws.append([
        r['Employee Name'],
        r['Department'],
        r['Region'],
        r['Product'],
        int(float(r['Q1 Sales'])),
        int(float(r['Q2 Sales'])),
        int(float(r['Q3 Sales'])),
        int(float(r['Q4 Sales'])),
        int(float(r['Total Sales']))
    ])

header_font = Font(bold=True)
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=5, max_col=9):
    for cell in row:
        cell.number_format = '$#,##0'

ws.column_dimensions['A'].width = 22
ws.column_dimensions['B'].width = 14
ws.column_dimensions['C'].width = 10
ws.column_dimensions['D'].width = 16
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 12
ws.column_dimensions['I'].width = 14

wb.save('/home/ga/Documents/employee_sales.xlsx')
print(f"Created employee sales file with {len(rows)} records from real Superstore dataset")

PYEOF

chown ga:ga "$EMPLOYEE_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the employee sales file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$EMPLOYEE_FILE"

echo "=== Task setup complete ==="
