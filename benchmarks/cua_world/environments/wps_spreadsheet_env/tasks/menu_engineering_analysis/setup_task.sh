#!/bin/bash
echo "=== Setting up menu_engineering_analysis task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

DATA_FILE="/home/ga/Documents/menu_sales_data.xlsx"

# Remove any existing file
rm -f "$DATA_FILE" 2>/dev/null || true

# Generate realistic POS data
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws = wb.active
ws.title = 'POS_Export'

# Headers
headers = ['Item_Name', 'Category', 'Qty_Sold', 'Unit_Cost', 'Unit_Price', 'Unit_CM', 'Total_Revenue', 'Total_CM', 'Classification']
ws.append(headers)

# Realistic restaurant data
items = [
    ("Truffle Fries", "Appetizer", 345, 2.50, 9.00),
    ("Calamari", "Appetizer", 210, 4.00, 12.00),
    ("Wagyu Burger", "Entree", 450, 8.50, 22.00),
    ("Ribeye 12oz", "Entree", 120, 18.00, 45.00),
    ("Mushroom Risotto", "Entree", 180, 3.50, 18.00),
    ("House Pinot Noir", "Beverage", 290, 4.00, 14.00),
    ("Craft IPA", "Beverage", 520, 1.50, 7.00),
    ("Caesar Salad", "Appetizer", 310, 2.00, 10.00),
    ("Seared Scallops", "Entree", 95, 12.00, 32.00),
    ("Lobster Mac", "Entree", 150, 9.00, 24.00),
    ("Iced Tea", "Beverage", 600, 0.25, 3.50),
    ("Chocolate Lava", "Dessert", 220, 2.50, 11.00),
    ("Cheesecake", "Dessert", 180, 3.00, 9.00),
    ("Oysters (Half Dozen)", "Appetizer", 140, 6.00, 18.00),
    ("Sparkling Water", "Beverage", 400, 1.00, 5.00),
    ("Roasted Chicken", "Entree", 250, 6.00, 21.00),
    ("Margherita Pizza", "Entree", 380, 3.00, 16.00),
    ("Espresso", "Beverage", 150, 0.50, 4.00),
    ("Tiramisu", "Dessert", 110, 2.00, 10.00),
    ("Brussels Sprouts", "Appetizer", 270, 2.00, 9.50)
]

for item in items:
    ws.append([item[0], item[1], item[2], item[3], item[4]])

# Format headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')

for cell in ws[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Currency formatting for cost/price
for row in ws.iter_rows(min_row=2, max_row=ws.max_row, min_col=4, max_col=5):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Column widths
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 12
ws.column_dimensions['D'].width = 12
ws.column_dimensions['E'].width = 12
ws.column_dimensions['F'].width = 12
ws.column_dimensions['G'].width = 15
ws.column_dimensions['H'].width = 15
ws.column_dimensions['I'].width = 18
ws.column_dimensions['J'].width = 12
ws.column_dimensions['K'].width = 12

wb.save('/home/ga/Documents/menu_sales_data.xlsx')
PYEOF

chown ga:ga "$DATA_FILE" 2>/dev/null || true

# Kill any existing WPS processes to avoid stale state
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Get X11 auth for ga user
GDM_XAUTH=$(ps aux | grep Xorg | grep -oP '(?<=-auth )\S+' | head -1)
if [ -n "$GDM_XAUTH" ] && [ -f "$GDM_XAUTH" ]; then
    cp "$GDM_XAUTH" /home/ga/.Xauthority 2>/dev/null || true
    chown ga:ga /home/ga/.Xauthority 2>/dev/null || true
fi

# Start WPS Spreadsheet
echo "Starting WPS Spreadsheet..."
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$DATA_FILE' &"
sleep 8

# Dismiss WPS dialogs (System Check and WPS Office default app dialog)
for attempt in 1 2 3; do
    echo "Dialog dismissal attempt $attempt..."

    # Close System Check dialog (Alt+F4)
    SYSCHECK_WIN=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "System Check" | awk '{print $1}')
    if [ -n "$SYSCHECK_WIN" ]; then
        echo "  Closing System Check dialog..."
        DISPLAY=:1 wmctrl -ia "$SYSCHECK_WIN" 2>/dev/null || true
        sleep 0.3
        su - ga -c "DISPLAY=:1 xdotool key alt+F4" 2>/dev/null || true
        sleep 2
    fi

    # Close WPS Office default app dialog (press Enter)
    WPS_DIALOG=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -i "WPS Office$" | awk '{print $1}')
    if [ -n "$WPS_DIALOG" ]; then
        echo "  Closing WPS Office dialog..."
        DISPLAY=:1 wmctrl -ia "$WPS_DIALOG" 2>/dev/null || true
        sleep 0.3
        su - ga -c "DISPLAY=:1 xdotool key Return" 2>/dev/null || true
        sleep 2
    fi

    # Check if dialogs are gone
    REMAINING=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "System Check|WPS Office$" | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo "  All dialogs cleared"
        break
    fi
    sleep 2
done

# Also try Escape for any remaining popups
su - ga -c "DISPLAY=:1 xdotool key Escape" 2>/dev/null || true
sleep 1

# Maximize and focus WPS Spreadsheet window
WPS_WIN=$(DISPLAY=:1 wmctrl -l 2>/dev/null | grep -iE "WPS Spreadsheets|\.xlsx|menu_sales" | head -1 | awk '{print $1}')
if [ -n "$WPS_WIN" ]; then
    DISPLAY=:1 wmctrl -ia "$WPS_WIN" 2>/dev/null || true
    DISPLAY=:1 wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz 2>/dev/null || true
else
    DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
    DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true
fi
sleep 1

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="