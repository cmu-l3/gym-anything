#!/bin/bash
echo "=== Setting up ecommerce_catalog_transformation task ==="

# Record task start time (for anti-gaming timestamp checks)
date +%s > /tmp/task_start_time.txt

CATALOG_FILE="/home/ga/Documents/retail_catalog.xlsx"
rm -f "$CATALOG_FILE" 2>/dev/null || true

# Generate realistic e-commerce data using Python
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()

# --- Sheet 1: Raw_Products ---
ws_raw = wb.active
ws_raw.title = "Raw_Products"

headers = ["Vendor_ID", "Product_Title", "Department", "Unit_Cost", "Stock_Level"]
ws_raw.append(headers)

departments = ["Footwear", "Apparel", "Electronics", "Home", "Outdoors"]
brands = {
    "Footwear": ["PUMA", "NK", "ADI", "NB", "VANS"],
    "Apparel": ["LEVI", "TNF", "PAT", "GILD", "CHMP"],
    "Electronics": ["SONY", "SAMS", "APL", "LG", "BOS"],
    "Home": ["OXO", "CUI", "KTA", "WMS", "DY"],
    "Outdoors": ["YETI", "COL", "MRM", "OSP", "BD"]
}

# Generate 50 realistic products
random.seed(42) # Deterministic data for robust verification
for i in range(50):
    dept = random.choice(departments)
    brand = random.choice(brands[dept])
    v_id = f"{brand}-{random.randint(1000, 9999)}"
    title = f"{brand} {dept} Product {i+1}"
    
    # Cost varies by dept
    if dept == "Electronics": cost = round(random.uniform(50.0, 300.0), 2)
    elif dept == "Footwear": cost = round(random.uniform(20.0, 80.0), 2)
    elif dept == "Outdoors": cost = round(random.uniform(15.0, 150.0), 2)
    else: cost = round(random.uniform(5.0, 40.0), 2)
    
    stock = random.randint(0, 100)
    ws_raw.append([v_id, title, dept, cost, stock])

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')
for cell in ws_raw[1]:
    cell.font = header_font
    cell.fill = header_fill

# --- Sheet 2: Margin_Rules ---
ws_margin = wb.create_sheet(title="Margin_Rules")
ws_margin.append(["Department", "Target_Margin"])

margin_data = {
    "Footwear": 0.40,
    "Apparel": 0.50,
    "Electronics": 0.25,
    "Home": 0.35,
    "Outdoors": 0.45
}
for dept, margin in margin_data.items():
    ws_margin.append([dept, margin])

# Format margin cells as percentage
for row in ws_margin.iter_rows(min_row=2, max_row=6, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '0%'

# Format headers
for cell in ws_margin[1]:
    cell.font = header_font
    cell.fill = header_fill

# Adjust column widths
ws_raw.column_dimensions['A'].width = 15
ws_raw.column_dimensions['B'].width = 30
ws_raw.column_dimensions['C'].width = 15
ws_raw.column_dimensions['D'].width = 12
ws_raw.column_dimensions['E'].width = 12
ws_margin.column_dimensions['A'].width = 15
ws_margin.column_dimensions['B'].width = 15

wb.save('/home/ga/Documents/retail_catalog.xlsx')
PYEOF

chown ga:ga "$CATALOG_FILE" 2>/dev/null || true

# Start WPS Spreadsheet if not running
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$CATALOG_FILE' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "retail_catalog"; then
        break
    fi
    sleep 1
done

# Maximize and focus
DISPLAY=:1 wmctrl -r "retail_catalog" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "retail_catalog" 2>/dev/null || true

# Take screenshot of initial state
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="