#!/bin/bash
echo "=== Setting up sort_and_filter_data task ==="

ORDERS_FILE="/home/ga/Documents/customer_orders.xlsx"

rm -f "$ORDERS_FILE" 2>/dev/null || true

# Create customer orders spreadsheet from real data (derived from Kaggle Superstore Sales dataset)
python3 << 'PYEOF'
import csv
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Read real customer order data from mounted CSV
csv_path = '/workspace/data/customer_orders.csv'
rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

wb = Workbook()
ws = wb.active
ws.title = 'Orders'

headers = ['Order ID', 'Customer Name', 'Product', 'Quantity', 'Order Date', 'Ship Date', 'Status', 'Amount']
ws.append(headers)

for r in rows:
    ws.append([
        r['Order ID'],
        r['Customer Name'],
        r['Product'],
        int(r['Quantity']),
        r['Order Date'],
        r['Ship Date'],
        r['Status'],
        float(r['Amount'])
    ])

header_font = Font(bold=True)
header_fill = PatternFill(start_color='4472C4', end_color='4472C4', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=8, max_col=8):
    for cell in row:
        cell.number_format = '$#,##0.00'

ws.column_dimensions['A'].width = 16
ws.column_dimensions['B'].width = 22
ws.column_dimensions['C'].width = 42
ws.column_dimensions['D'].width = 10
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 12
ws.column_dimensions['H'].width = 12

wb.save('/home/ga/Documents/customer_orders.xlsx')
print(f"Created customer orders file with {len(rows)} orders from real Superstore dataset")

PYEOF

chown ga:ga "$ORDERS_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the customer orders file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$ORDERS_FILE"

echo "=== Task setup complete ==="
