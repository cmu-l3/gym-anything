#!/bin/bash
echo "=== Setting up retail_markdown_optimization task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

INVENTORY_FILE="/home/ga/Documents/retail_inventory.xlsx"
rm -f "$INVENTORY_FILE" 2>/dev/null || true

# Generate highly realistic retail dataset inside the container
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = 'Inventory'

headers = ['SKU', 'Product_Name', 'Category', 'Initial_Qty', 'Units_Sold', 'Current_Price']
ws.append(headers)

categories = {
    'Outerwear': ['Jacket', 'Coat', 'Parka', 'Windbreaker', 'Vest'],
    'Tops': ['T-Shirt', 'Blouse', 'Sweater', 'Hoodie', 'Tank Top'],
    'Bottoms': ['Jeans', 'Chinos', 'Shorts', 'Skirt', 'Leggings'],
    'Footwear': ['Sneakers', 'Boots', 'Sandals', 'Loafers', 'Heels'],
    'Accessories': ['Hat', 'Scarf', 'Belt', 'Gloves', 'Sunglasses']
}

random.seed(42) # Deterministic data for predictable verification

# Generate 250 items
for i in range(1, 251):
    cat = random.choice(list(categories.keys()))
    prod_type = random.choice(categories[cat])
    color = random.choice(['Black', 'White', 'Navy', 'Red', 'Grey', 'Olive'])
    prod_name = f"{color} {prod_type}"
    sku = f"{cat[:3].upper()}-{i:04d}"
    
    initial = random.randint(50, 500)
    
    # Force some items to have 0 sales to test the Div/0 requirement
    if i % 25 == 0:
        sold = 0
    else:
        # Realistic sell-through between 10% and 95%
        sold = int(initial * random.uniform(0.1, 0.95))
        
    price = round(random.uniform(15.0, 250.0), 2)
    
    ws.append([sku, prod_name, cat, initial, sold, price])

# Add Markdown Rules sheet
ws2 = wb.create_sheet('Markdown_Rules')
ws2.append(['Min_WOS', 'Markdown_Pct'])
rules = [
    [0, 0.00],
    [4, 0.15],
    [8, 0.30],
    [12, 0.50],
    [20, 0.75]
]
for r in rules:
    ws2.append(r)

# Format Inventory sheet
header_font = Font(bold=True, color="FFFFFF")
header_fill = PatternFill(start_color='203764', end_color='203764', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=6, max_col=6):
    for cell in row:
        cell.number_format = '$#,##0.00'

ws.column_dimensions['A'].width = 12
ws.column_dimensions['B'].width = 25
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 15

# Format Rules sheet
for cell in ws2[1]:
    cell.font = Font(bold=True)
for row in ws2.iter_rows(min_row=2, max_row=ws2.max_row, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '0%'

wb.save('/home/ga/Documents/retail_inventory.xlsx')
print(f"Created retail inventory file with 250 records.")
PYEOF

chown ga:ga "$INVENTORY_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$INVENTORY_FILE' &"
    sleep 6
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "retail_inventory"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "retail_inventory" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "retail_inventory" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="