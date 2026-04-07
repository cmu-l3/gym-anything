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

# Launch WPS Spreadsheet with the inventory file
echo "Launching WPS Spreadsheet with inventory file..."

# Kill any existing WPS processes
pkill -x et 2>/dev/null || true
pkill -f "/office6/et" 2>/dev/null || true
sleep 2

# Get X11 auth
GDM_XAUTH=$(ps aux | grep Xorg | grep -oP '(?<=-auth )\S+' | head -1)
if [ -n "$GDM_XAUTH" ] && [ -f "$GDM_XAUTH" ]; then
    cp "$GDM_XAUTH" /home/ga/.Xauthority
    chown ga:ga /home/ga/.Xauthority
fi

su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; et '$INVENTORY_FILE' &"
sleep 8

# Wait for WPS window
for i in $(seq 1 30); do
    if su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -qi "inventory\|WPS Spreadsheets\|et"; then
        echo "WPS Spreadsheet window detected after ${i}s"
        break
    fi
    sleep 1
done

# Maximize the window
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true

# Dismiss all first-run dialogs repeatedly (System Check, WPS Office default app, etc.)
# Dialogs may appear with a delay, so retry a few times
for _attempt in 1 2 3; do
    sleep 3

    # Close System Check dialog via Alt+F4
    SYSCHECK_WIN=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -i "System Check" | awk '{print $1}')
    if [ -n "$SYSCHECK_WIN" ]; then
        echo "Dismissing System Check dialog (attempt $_attempt)..."
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$SYSCHECK_WIN'" 2>/dev/null || true
        sleep 0.5
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key alt+F4" 2>/dev/null || true
        sleep 1
    fi

    # Close "WPS Office" default office software dialog by pressing Enter (clicks OK)
    WPS_DIALOG=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -i "WPS Office$" | awk '{print $1}')
    if [ -n "$WPS_DIALOG" ]; then
        echo "Dismissing WPS Office dialog (attempt $_attempt)..."
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$WPS_DIALOG'" 2>/dev/null || true
        sleep 0.5
        su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Return" 2>/dev/null || true
        sleep 1
    fi

    # If no dialogs found, break out
    REMAINING=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -iE "System Check|WPS Office$" | wc -l)
    if [ "$REMAINING" -eq 0 ]; then
        echo "All dialogs dismissed"
        break
    fi
done

# Close any remaining dialogs with Escape
su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; xdotool key Escape" 2>/dev/null || true
sleep 1

# Re-focus and maximize the spreadsheet window
WPS_WIN=$(su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -l" 2>/dev/null | grep -i "inventory\|WPS Spreadsheets" | head -1 | awk '{print $1}')
if [ -n "$WPS_WIN" ]; then
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -ia '$WPS_WIN'" 2>/dev/null || true
    su - ga -c "export DISPLAY=:1; export XAUTHORITY=/home/ga/.Xauthority; wmctrl -r :ACTIVE: -b add,maximized_vert,maximized_horz" 2>/dev/null || true
fi

echo "=== Task setup complete ==="
