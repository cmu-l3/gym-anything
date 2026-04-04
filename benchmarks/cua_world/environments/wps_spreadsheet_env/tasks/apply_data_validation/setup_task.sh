#!/bin/bash
echo "=== Setting up apply_data_validation task ==="

PROJECT_FILE="/home/ga/Documents/project_tracker.xlsx"

rm -f "$PROJECT_FILE" 2>/dev/null || true

# Create project tracker from real data (derived from Kaggle Superstore Sales dataset - major orders)
python3 << 'PYEOF'
import csv
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Read real project tracker data from mounted CSV
csv_path = '/workspace/data/project_tracker.csv'
rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

wb = Workbook()
ws = wb.active
ws.title = 'Projects'

headers = ['Project Name', 'Start Date', 'End Date', 'Budget', 'Status', 'Priority', 'Assigned To']
ws.append(headers)

for r in rows:
    ws.append([
        r['Project Name'],
        r['Start Date'],
        r['End Date'],
        int(float(r['Budget'])),
        r['Status'],
        r['Priority'],
        r['Assigned To']
    ])

header_font = Font(bold=True)
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=4, max_col=4):
    for cell in row:
        cell.number_format = '$#,##0'

ws.column_dimensions['A'].width = 32
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 14
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 14

wb.save('/home/ga/Documents/project_tracker.xlsx')
print(f"Created project tracker file with {len(rows)} projects from real Superstore dataset")

PYEOF

chown ga:ga "$PROJECT_FILE" 2>/dev/null || true

echo "=== Task setup complete ==="
