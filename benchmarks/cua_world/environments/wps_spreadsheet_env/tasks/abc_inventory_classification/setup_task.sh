#!/bin/bash
echo "=== Setting up ABC Inventory Classification task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

INVENTORY_FILE="/home/ga/Documents/inventory_abc_analysis.xlsx"
rm -f "$INVENTORY_FILE" 2>/dev/null || true

# Generate realistic inventory data
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Use fixed seed for deterministic ground truth
random.seed(42)

wb = Workbook()
ws = wb.active
ws.title = 'Inventory'

# Headers
headers = ['SKU', 'Description', 'Annual_Demand', 'Unit_Cost']
ws.append(headers)

# Generate 250 items with pareto-like distribution for demand to simulate real ABC curve
demand_values = [int(random.paretovariate(1.1) * 100) for _ in range(250)]
random.shuffle(demand_values)

for i in range(1, 251):
    sku = f"SKU-{10000+i}"
    desc = f"Inventory Item {chr(65 + (i%26))}-{i}"
    demand = demand_values[i-1] + 10  # Ensure at least 10
    cost = round(random.uniform(5.0, 500.0), 2)
    ws.append([sku, desc, demand, cost])

# Format header row
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Number formats
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '#,##0'

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=4, max_col=4):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Adjust widths
ws.column_dimensions['A'].width = 15
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 18
ws.column_dimensions['D'].width = 15

wb.save('/home/ga/Documents/inventory_abc_analysis.xlsx')
print(f"Created inventory file with 250 SKUs.")
PYEOF

chown ga:ga "$INVENTORY_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the file
if ! pgrep -f "et " > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$INVENTORY_FILE' &"
    sleep 5
fi

# Wait for window
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "inventory_abc_analysis"; then
        break
    fi
    sleep 1
done

# Maximize window
DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a :ACTIVE: 2>/dev/null || true

# Take initial screenshot
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="