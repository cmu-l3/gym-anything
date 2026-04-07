#!/bin/bash
set -e
echo "=== Setting up build_depreciation_schedule task ==="

# Record task start time for anti-gaming verification
date +%s > /tmp/task_start_time.txt

# Target file paths
DOCS_DIR="/home/ga/Documents"
INPUT_FILE="$DOCS_DIR/asset_register.xlsx"
OUTPUT_FILE="$DOCS_DIR/depreciation_schedule.xlsx"

mkdir -p "$DOCS_DIR"
rm -f "$INPUT_FILE" "$OUTPUT_FILE" 2>/dev/null || true

# Generate the starting workbook using Python and openpyxl
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()

# 1. Setup Asset Register Sheet
ws_assets = wb.active
ws_assets.title = "Asset_Register"

asset_headers = ["Asset_ID", "Description", "Category", "Acquisition_Date", "Cost", "Salvage_Value", "Useful_Life_Years", "MACRS_Class"]
ws_assets.append(asset_headers)

# Real-world inspired fixed asset data
assets = [
    ("FA-001", "CNC Mill", "Machinery", "2021-03-15", 125000, 12500, 10, 7),
    ("FA-002", "Lathe", "Machinery", "2021-04-10", 85000, 8500, 10, 7),
    ("FA-003", "Press Brake", "Machinery", "2021-05-20", 95000, 9500, 10, 7),
    ("FA-004", "Welding Station", "Machinery", "2021-06-11", 25000, 2500, 10, 7),
    ("FA-005", "Band Saw", "Machinery", "2021-07-08", 15000, 1500, 10, 7),
    ("FA-006", "Delivery Truck A", "Vehicles", "2021-01-10", 48000, 6000, 5, 5),
    ("FA-007", "Delivery Truck B", "Vehicles", "2021-01-12", 48000, 6000, 5, 5),
    ("FA-008", "Forklift 1", "Vehicles", "2021-02-15", 35000, 3500, 5, 5),
    ("FA-009", "Forklift 2", "Vehicles", "2021-02-15", 35000, 3500, 5, 5),
    ("FA-010", "Main Server", "IT Equipment", "2021-01-05", 45000, 0, 5, 5),
    ("FA-011", "Server Rack", "IT Equipment", "2021-01-06", 32000, 2000, 5, 5),
    ("FA-012", "Workstations Set A", "IT Equipment", "2021-01-15", 25000, 0, 5, 5),
    ("FA-013", "Network Switches", "IT Equipment", "2021-01-20", 18000, 0, 5, 5),
    ("FA-014", "Exec Desks", "Office Furniture", "2021-02-01", 12000, 1200, 10, 7),
    ("FA-015", "Office Chairs", "Office Furniture", "2021-02-05", 8500, 500, 10, 7),
    ("FA-016", "Filing Cabinets", "Office Furniture", "2021-02-10", 4500, 0, 10, 7),
    ("FA-017", "Conf Table", "Office Furniture", "2021-02-15", 6000, 500, 10, 7),
    ("FA-018", "HVAC Upgrade", "Building Improvements", "2021-05-01", 150000, 0, 15, 15),
    ("FA-019", "Loading Dock", "Building Improvements", "2021-06-15", 85000, 0, 15, 15),
    ("FA-020", "Lighting Retrofit", "Building Improvements", "2021-08-20", 45000, 0, 15, 15)
]

for asset in assets:
    ws_assets.append(asset)

# Style headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='D9E1F2', end_color='D9E1F2', fill_type='solid')
for cell in ws_assets[1]:
    cell.font = header_font
    cell.fill = header_fill

# Format Currency
for row in ws_assets.iter_rows(min_row=2, max_row=21, min_col=5, max_col=6):
    for cell in row:
        cell.number_format = '$#,##0.00'

# Adjust columns
for col in ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']:
    ws_assets.column_dimensions[col].width = 16
ws_assets.column_dimensions['B'].width = 25

# 2. Setup MACRS Table Sheet (IRS Pub 946 Table A-1 Half-year convention)
ws_macrs = wb.create_sheet("MACRS_Tables")
macrs_headers = ["Recovery_Year", "3", "5", "7", "10", "15", "20"] # Note headers are the class years
ws_macrs.append(macrs_headers)

# Rates converted to decimals for easy spreadsheet calculation
macrs_rates = [
    [1, 0.3333, 0.2000, 0.1429, 0.1000, 0.0500, 0.0375],
    [2, 0.4445, 0.3200, 0.2449, 0.1800, 0.0950, 0.07219],
    [3, 0.1481, 0.1920, 0.1749, 0.1440, 0.0855, 0.06677],
    [4, 0.0741, 0.1152, 0.1249, 0.1152, 0.0770, 0.06177],
    [5, 0.0000, 0.1152, 0.0893, 0.0922, 0.0693, 0.05713],
    [6, 0.0000, 0.0576, 0.0892, 0.0737, 0.0623, 0.05285],
    [7, 0.0000, 0.0000, 0.0893, 0.0655, 0.0590, 0.04888],
    [8, 0.0000, 0.0000, 0.0446, 0.0655, 0.0590, 0.04522],
    [9, 0.0000, 0.0000, 0.0000, 0.0656, 0.0591, 0.04462],
    [10, 0.0000, 0.0000, 0.0000, 0.0655, 0.0590, 0.04461],
    [11, 0.0000, 0.0000, 0.0000, 0.0328, 0.0591, 0.04462],
    [12, 0.0000, 0.0000, 0.0000, 0.0000, 0.0590, 0.04461],
    [13, 0.0000, 0.0000, 0.0000, 0.0000, 0.0591, 0.04462],
    [14, 0.0000, 0.0000, 0.0000, 0.0000, 0.0590, 0.04461],
    [15, 0.0000, 0.0000, 0.0000, 0.0000, 0.0591, 0.04462],
    [16, 0.0000, 0.0000, 0.0000, 0.0000, 0.0295, 0.04461]
]

for row in macrs_rates:
    ws_macrs.append(row)

for cell in ws_macrs[1]:
    cell.font = header_font
    cell.fill = header_fill

for row in ws_macrs.iter_rows(min_row=2, max_row=17, min_col=2, max_col=7):
    for cell in row:
        cell.number_format = '0.00%'

wb.save('/home/ga/Documents/asset_register.xlsx')
PYEOF

chown ga:ga "$INPUT_FILE"

# Start WPS Spreadsheet
if ! pgrep -f "et" > /dev/null; then
    echo "Starting WPS Spreadsheet..."
    su - ga -c "DISPLAY=:1 et '$INPUT_FILE' &"
    sleep 5
fi

# Wait for window to appear
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "WPS Spreadsheets"; then
        break
    fi
    sleep 1
done

# Maximize the window
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "WPS Spreadsheets" 2>/dev/null || true

# Close any popups
DISPLAY=:1 xdotool key Escape 2>/dev/null || true

# Take initial screenshot
DISPLAY=:1 scrot /tmp/task_initial_state.png 2>/dev/null || true

echo "=== Task setup complete ==="