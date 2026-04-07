#!/bin/bash
set -e
echo "=== Setting up build_site_selection_model task ==="

# Record task start time (for anti-gaming verification)
date +%s > /tmp/task_start_time.txt

# Ensure directories exist
mkdir -p /home/ga/Documents

# Create the initial spreadsheet with real US Census/Market data
python3 << 'PYEOF'
import os
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()

# 1. Create Weights Sheet
ws_weights = wb.active
ws_weights.title = 'Weights'
ws_weights.append(['Metric', 'Weight'])
ws_weights.append(['Population', 0.30])
ws_weights.append(['Income', 0.20])
ws_weights.append(['Competitor', 0.20])
ws_weights.append(['Lease', 0.30])

header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9D9D9', end_color='D9D9D9', fill_type='solid')

for cell in ws_weights[1]:
    cell.font = header_font
    cell.fill = header_fill

# Format weights as percentages
for row in ws_weights.iter_rows(min_row=2, max_row=5, min_col=2, max_col=2):
    for cell in row:
        cell.number_format = '0%'

ws_weights.column_dimensions['A'].width = 15
ws_weights.column_dimensions['B'].width = 12

# 2. Create Sites Sheet with embedded real-world demographic/market data
ws_sites = wb.create_sheet('Sites')
headers = ['Site_ID', 'Zip_Code', 'City', 'State', 'Pop_Density_SqMi', 'Median_Income', 'Competitor_Distance_Mi', 'Lease_Rate_SqFt']
ws_sites.append(headers)

real_data = [
    ["10001", "New York", "NY", 28211, 93000, 0.2, 85.50],
    ["90001", "Los Angeles", "CA", 8359, 68000, 0.8, 55.00],
    ["60601", "Chicago", "IL", 11841, 73000, 1.1, 42.00],
    ["77001", "Houston", "TX", 3501, 53000, 2.5, 28.50],
    ["85001", "Phoenix", "AZ", 3105, 60000, 3.0, 25.00],
    ["19102", "Philadelphia", "PA", 11683, 49000, 1.5, 35.00],
    ["78201", "San Antonio", "TX", 3032, 53000, 3.2, 22.00],
    ["92101", "San Diego", "CA", 4325, 83000, 1.8, 48.00],
    ["75201", "Dallas", "TX", 3866, 54000, 2.8, 30.00],
    ["95101", "San Jose", "CA", 5777, 115000, 1.4, 52.00],
    ["78701", "Austin", "TX", 3006, 75000, 2.1, 38.00],
    ["32202", "Jacksonville", "FL", 1221, 55000, 4.5, 18.00],
    ["94102", "San Francisco", "CA", 18635, 119000, 0.4, 78.00],
    ["43215", "Columbus", "OH", 3932, 54000, 2.5, 24.00],
    ["46204", "Indianapolis", "IN", 2366, 48000, 3.5, 20.00],
    ["98101", "Seattle", "WA", 8775, 92000, 1.2, 45.00],
    ["80202", "Denver", "CO", 4521, 72000, 2.0, 36.00],
    ["20001", "Washington", "DC", 11280, 90000, 0.9, 50.00],
    ["02108", "Boston", "MA", 13938, 76000, 0.7, 58.00],
    ["37201", "Nashville", "TN", 1391, 62000, 3.8, 29.00],
    ["28202", "Charlotte", "NC", 2772, 65000, 2.9, 27.00],
    ["48226", "Detroit", "MI", 4710, 32000, 4.0, 19.00],
    ["97204", "Portland", "OR", 4740, 73000, 2.2, 34.00],
    ["30303", "Atlanta", "GA", 3549, 64000, 2.6, 31.00],
    ["33132", "Miami", "FL", 12271, 44000, 1.1, 46.00]
]

for idx, row in enumerate(real_data, 1):
    ws_sites.append([f"S{idx:03d}"] + row)

for cell in ws_sites[1]:
    cell.font = header_font
    cell.fill = header_fill

# Format currency and numbers
for row in ws_sites.iter_rows(min_row=2, max_row=len(real_data)+1):
    row[4].number_format = '#,##0'       # Density
    row[5].number_format = '$#,##0'      # Income
    row[6].number_format = '0.0'         # Comp distance
    row[7].number_format = '$#,##0.00'   # Lease Rate

# Auto-size columns
for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']:
    ws_sites.column_dimensions[col].width = 16

# Make Sites the active sheet when opening
wb.active = 1

wb.save('/home/ga/Documents/store_locations.xlsx')
PYEOF

chown ga:ga /home/ga/Documents/store_locations.xlsx

# Ensure application is running
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/store_locations.xlsx &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "store_locations"; then
        break
    fi
    sleep 1
done

# Maximize and focus the window
DISPLAY=:1 wmctrl -r "store_locations" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "store_locations" 2>/dev/null || true

# Dismiss any startup dialogs
DISPLAY=:1 xdotool key Escape 2>/dev/null || true
sleep 1

# Take initial state screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="