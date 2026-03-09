#!/bin/bash
echo "=== Setting up add_conditional_formatting task ==="

INVENTORY_FILE="/home/ga/Documents/inventory.xlsx"

rm -f "$INVENTORY_FILE" 2>/dev/null || true

# Create inventory spreadsheet from real data (Montgomery County MD Warehouse & Retail Sales)
python3 << 'PYEOF'
import csv
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Read real inventory data from mounted CSV (derived from Data.gov warehouse/retail sales)
csv_path = '/workspace/data/inventory.csv'
rows = []
with open(csv_path, 'r') as f:
    reader = csv.DictReader(f)
    for r in reader:
        rows.append(r)

wb = Workbook()
ws = wb.active
ws.title = 'Inventory'

# Headers
headers = ['Item Name', 'SKU', 'Quantity', 'Reorder Level', 'Unit Price', 'Supplier']
ws.append(headers)

# Add real data
for r in rows:
    ws.append([
        r['Item Name'],
        r['SKU'],
        int(r['Quantity']),
        int(r['Reorder Level']),
        float(r['Unit Price']),
        r['Supplier']
    ])

# Format header row
header_font = Font(bold=True)
header_fill = PatternFill(start_color='366092', end_color='366092', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Format currency
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=5, max_col=5):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Auto-adjust column widths
ws.column_dimensions['A'].width = 40
ws.column_dimensions['B'].width = 12
ws.column_dimensions['C'].width = 10
ws.column_dimensions['D'].width = 14
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 30

wb.save('/home/ga/Documents/inventory.xlsx')
print(f"Created inventory file with {len(rows)} items from real warehouse/retail sales data")

PYEOF

chown ga:ga "$INVENTORY_FILE" 2>/dev/null || true

echo "=== Task setup complete ==="
