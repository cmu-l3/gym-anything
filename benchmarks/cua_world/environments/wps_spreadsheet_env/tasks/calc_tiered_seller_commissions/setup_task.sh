#!/bin/bash
echo "=== Setting up calc_tiered_seller_commissions task ==="

TARGET_FILE="/home/ga/Documents/seller_commissions.xlsx"

# Record task start time
date +%s > /tmp/task_start_time.txt

# Remove any old file
rm -f "$TARGET_FILE" 2>/dev/null || true

# Generate realistic e-commerce data
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

# Set seed for reproducible realistic data
random.seed(42)

wb = Workbook()

# 1. Create Orders Sheet
ws_orders = wb.active
ws_orders.title = 'Orders'
headers = ['order_id', 'product_id', 'seller_id', 'price']
ws_orders.append(headers)

# Generate 45 unique sellers
sellers = [f"seller_{str(i).zfill(2)}" for i in range(1, 46)]

# Generate 1500 realistic orders
for i in range(1500):
    order_id = f"ORD-{random.randint(10000, 99999)}-{random.randint(1000, 9999)}"
    product_id = f"PRD-{random.randint(100, 999)}"
    seller_id = random.choice(sellers)
    
    # Generate realistic prices (skewed towards lower values)
    price = round(random.expovariate(1/150) + 10.0, 2)
    ws_orders.append([order_id, product_id, seller_id, price])

# 2. Create Tiers Sheet
ws_tiers = wb.create_sheet(title='Tiers')
ws_tiers.append(['Min_Sales', 'Max_Sales', 'Commission_Rate'])
ws_tiers.append([0, 4999.99, 0.10])
ws_tiers.append([5000, 14999.99, 0.08])
ws_tiers.append([15000, 49999.99, 0.06])
ws_tiers.append([50000, 999999.99, 0.05])

for row in ws_tiers.iter_rows(min_row=2, max_row=5, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '0.00%'

# 3. Create Payouts Sheet
ws_payouts = wb.create_sheet(title='Payouts')
payout_headers = ['seller_id', 'Total_Sales', 'Commission_Rate', 'Commission_Amount', 'Marketplace_Net']
ws_payouts.append(payout_headers)

for seller in sorted(sellers):
    ws_payouts.append([seller])

# Formatting
header_font = Font(bold=True)
header_fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')

for ws in [ws_orders, ws_tiers, ws_payouts]:
    for cell in ws[1]:
        cell.font = header_font
        cell.fill = header_fill
        cell.alignment = Alignment(horizontal='center')

ws_orders.column_dimensions['A'].width = 20
ws_orders.column_dimensions['B'].width = 15
ws_orders.column_dimensions['C'].width = 15
ws_orders.column_dimensions['D'].width = 12

ws_tiers.column_dimensions['A'].width = 15
ws_tiers.column_dimensions['B'].width = 15
ws_tiers.column_dimensions['C'].width = 18

ws_payouts.column_dimensions['A'].width = 15
ws_payouts.column_dimensions['B'].width = 15
ws_payouts.column_dimensions['C'].width = 18
ws_payouts.column_dimensions['D'].width = 20
ws_payouts.column_dimensions['E'].width = 20

wb.save('/home/ga/Documents/seller_commissions.xlsx')
print("Created seller_commissions.xlsx with realistic dataset")
PYEOF

# Ensure proper ownership
chown ga:ga "$TARGET_FILE" 2>/dev/null || true

# Start WPS Spreadsheet
if ! pgrep -f "et " > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$TARGET_FILE' &"
    sleep 6
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "seller_commissions\|Spreadsheet"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "seller_commissions" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "seller_commissions" 2>/dev/null || true

# Take screenshot of initial state
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="