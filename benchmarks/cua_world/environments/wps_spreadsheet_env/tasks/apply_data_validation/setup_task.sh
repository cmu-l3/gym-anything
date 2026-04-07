#!/bin/bash
echo "=== Setting up apply_data_validation task ==="

TRACKER_FILE="/home/ga/Documents/project_tracker.xlsx"

rm -f "$TRACKER_FILE" 2>/dev/null || true

# Create project tracker spreadsheet from real data (derived from Kaggle Superstore Sales dataset)
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
        float(r['Budget']),
        r['Status'],
        r['Priority'],
        r['Assigned To']
    ])

# Format header row
header_font = Font(bold=True)
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Format currency column (Budget = col 4)
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=4, max_col=4):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Auto-adjust column widths
ws.column_dimensions['A'].width = 36
ws.column_dimensions['B'].width = 14
ws.column_dimensions['C'].width = 14
ws.column_dimensions['D'].width = 14
ws.column_dimensions['E'].width = 14
ws.column_dimensions['F'].width = 10
ws.column_dimensions['G'].width = 14

wb.save('/home/ga/Documents/project_tracker.xlsx')
print(f"Created project tracker file with {len(rows)} projects from real Superstore dataset")

PYEOF

chown ga:ga "$TRACKER_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the project tracker file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$TRACKER_FILE"

echo "=== Task setup complete ==="
