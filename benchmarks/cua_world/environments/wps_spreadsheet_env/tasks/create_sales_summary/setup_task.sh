#!/bin/bash
# set -euo pipefail

echo "=== Setting up create_sales_summary task ==="

# Create sample sales data file from real Superstore dataset
SALES_FILE="/home/ga/Documents/sales_data.xlsx"

# Remove old files
rm -f "$SALES_FILE" 2>/dev/null || true
rm -f /tmp/sales_result.json 2>/dev/null || true

# Create sales data from real CSV (derived from Kaggle Superstore Sales dataset)
python3 << 'PYEOF'
import csv
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Read real sales data from mounted CSV (Superstore Sales dataset)
csv_path = '/workspace/data/sales_data.csv'
rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

# Create workbook from real data
wb = Workbook()
ws = wb.active
ws.title = 'Sales Data'

# Headers
headers = ['Date', 'Product', 'Category', 'Quantity', 'Unit Price', 'Region', 'Salesperson', 'Total']
ws.append(headers)

# Add real data rows
for r in rows:
    ws.append([
        r['Date'],
        r['Product'],
        r['Category'],
        int(r['Quantity']),
        float(r['Unit_Price']),
        r['Region'],
        r['Salesperson'],
        float(r['Total'])
    ])

# Format header row
header_font = Font(bold=True)
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')
header_alignment = Alignment(horizontal='center')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = header_alignment

# Format currency columns (Unit Price = col 5, Total = col 8)
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=5, max_col=5):
    for cell in row:
        cell.number_format = '$#,##0.00'

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=8, max_col=8):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Auto-adjust column widths
ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 42
ws.column_dimensions['C'].width = 16
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 10
ws.column_dimensions['G'].width = 18
ws.column_dimensions['H'].width = 12

# Save
wb.save('/home/ga/Documents/sales_data.xlsx')
print(f"Created sales data file with {ws.max_row - 1} records from real Superstore dataset")

PYEOF

# Ensure proper ownership
chown ga:ga "$SALES_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the sales data file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$SALES_FILE"

echo "=== Task setup complete ==="
