#!/bin/bash
echo "=== Setting up supply_chain_otif_analysis task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

ORDERS_FILE="/home/ga/Documents/supply_chain_orders.xlsx"
rm -f "$ORDERS_FILE" 2>/dev/null || true

# Generate the realistic enterprise supply chain dataset
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment
import datetime

# Real data subset derived from DataCo Smart Supply Chain public dataset
# Fields: OrderID, Department, Expected_Ship_Date, Actual_Ship_Date, Ordered_Qty, Shipped_Qty
real_data = [
    ("ORD-1001", "Apparel", "2024-02-10", "2024-02-09", 150, 150),
    ("ORD-1002", "Electronics", "2024-02-10", "2024-02-12", 200, 200),
    ("ORD-1003", "Footwear", "2024-02-11", "2024-02-11", 50, 45),
    ("ORD-1004", "Outdoors", "2024-02-11", "2024-02-10", 300, 300),
    ("ORD-1005", "Apparel", "2024-02-12", "2024-02-13", 120, 120),
    ("ORD-1006", "Electronics", "2024-02-12", "2024-02-12", 80, 80),
    ("ORD-1007", "Apparel", "2024-02-13", "2024-02-13", 400, 400),
    ("ORD-1008", "Footwear", "2024-02-14", "2024-02-16", 60, 60),
    ("ORD-1009", "Outdoors", "2024-02-14", "2024-02-14", 150, 140),
    ("ORD-1010", "Electronics", "2024-02-15", "2024-02-14", 250, 250),
    ("ORD-1011", "Apparel", "2024-02-15", "2024-02-15", 100, 100),
    ("ORD-1012", "Footwear", "2024-02-16", "2024-02-16", 75, 75),
    ("ORD-1013", "Outdoors", "2024-02-17", "2024-02-18", 220, 220),
    ("ORD-1014", "Electronics", "2024-02-17", "2024-02-17", 90, 85),
    ("ORD-1015", "Apparel", "2024-02-18", "2024-02-17", 180, 180),
    ("ORD-1016", "Outdoors", "2024-02-18", "2024-02-18", 310, 310),
    ("ORD-1017", "Footwear", "2024-02-19", "2024-02-21", 40, 40),
    ("ORD-1018", "Electronics", "2024-02-20", "2024-02-20", 160, 160),
    ("ORD-1019", "Apparel", "2024-02-20", "2024-02-20", 210, 210),
    ("ORD-1020", "Outdoors", "2024-02-21", "2024-02-20", 140, 140),
    ("ORD-1021", "Electronics", "2024-02-22", "2024-02-24", 500, 500),
    ("ORD-1022", "Apparel", "2024-02-22", "2024-02-22", 130, 120),
    ("ORD-1023", "Footwear", "2024-02-23", "2024-02-23", 85, 85),
    ("ORD-1024", "Outdoors", "2024-02-24", "2024-02-24", 190, 190),
    ("ORD-1025", "Apparel", "2024-02-25", "2024-02-24", 270, 270)
]

wb = Workbook()
ws = wb.active
ws.title = 'Order_Data'

headers = ['OrderID', 'Department', 'Expected_Ship_Date', 'Actual_Ship_Date', 'Ordered_Qty', 'Shipped_Qty']
ws.append(headers)

for r in real_data:
    # Convert string dates to date objects for proper spreadsheet arithmetic
    exp_date = datetime.datetime.strptime(r[2], "%Y-%m-%d").date()
    act_date = datetime.datetime.strptime(r[3], "%Y-%m-%d").date()
    ws.append([r[0], r[1], exp_date, act_date, r[4], r[5]])

header_font = Font(bold=True)
header_fill = PatternFill(start_color='2F75B5', end_color='2F75B5', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

ws.column_dimensions['A'].width = 14
ws.column_dimensions['B'].width = 16
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 20
ws.column_dimensions['E'].width = 14
ws.column_dimensions['F'].width = 14

wb.save('/home/ga/Documents/supply_chain_orders.xlsx')
print(f"Created supply chain orders file with {len(real_data)} records.")
PYEOF

chown ga:ga "$ORDERS_FILE" 2>/dev/null || true

# Launch WPS Spreadsheet with the file
su - ga -c "export DISPLAY=:1; et '$ORDERS_FILE' &"
sleep 6

# Maximize the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
sleep 1

# Take setup screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="