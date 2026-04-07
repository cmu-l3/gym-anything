#!/bin/bash
echo "=== Setting up build_construction_bid_estimate task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

TAKEOFF_FILE="/home/ga/Documents/residential_takeoff.xlsx"
rm -f "$TAKEOFF_FILE" 2>/dev/null || true

# Generate realistic construction dataset using python openpyxl
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws_master = wb.active
ws_master.title = 'Master_Price_Book'

# --- Master Price Book Data ---
headers_master = ['Item_Code', 'CSI_Division', 'Description', 'Unit', 'Material_Unit_Cost', 'Labor_Unit_Cost']
ws_master.append(headers_master)

master_data = [
    ['CON-001', '03-Concrete', '3000 PSI Concrete', 'CY', 125.00, 45.00],
    ['CON-002', '03-Concrete', 'Rebar #4', 'LF', 0.85, 1.15],
    ['CON-003', '03-Concrete', 'Formwork', 'SF', 2.50, 4.00],
    ['WOD-001', '06-Wood and Plastics', '2x4x8 Stud', 'EA', 4.50, 2.50],
    ['WOD-002', '06-Wood and Plastics', '1/2" OSB Plywood', 'SHT', 18.00, 8.00],
    ['WOD-003', '06-Wood and Plastics', 'Roof Trusses', 'EA', 150.00, 50.00],
    ['FIN-001', '09-Finishes', '1/2" Drywall', 'SHT', 14.00, 22.00],
    ['FIN-002', '09-Finishes', 'Interior Paint', 'GAL', 35.00, 40.00],
    ['FIN-003', '09-Finishes', 'Baseboard Trim', 'LF', 1.25, 2.00],
    ['ELE-001', '26-Electrical', '14/2 Romex Wire', 'LF', 0.65, 1.20],
    ['ELE-002', '26-Electrical', 'Standard Receptacle', 'EA', 3.50, 15.00],
    ['PLM-001', '22-Plumbing', '1/2" PEX Pipe', 'LF', 0.45, 2.50]
]

for row in master_data:
    ws_master.append(row)

# Format master headers
header_font = Font(bold=True, color='FFFFFF')
header_fill = PatternFill(start_color='4F81BD', end_color='4F81BD', fill_type='solid')
for cell in ws_master[1]:
    cell.font = header_font
    cell.fill = header_fill

for row in ws_master.iter_rows(min_row=2, max_row=ws_master.max_row, min_col=5, max_col=6):
    for cell in row:
        cell.number_format = '$#,##0.00'

ws_master.column_dimensions['B'].width = 25
ws_master.column_dimensions['C'].width = 25
ws_master.column_dimensions['E'].width = 18
ws_master.column_dimensions['F'].width = 18

# --- Project Takeoff Data ---
ws_takeoff = wb.create_sheet('Project_Takeoff')
headers_takeoff = ['Item_Code', 'Plan_Quantity', 'Waste_Factor_Pct', 'Description', 'CSI_Division', 'Adj_Material_Qty', 'Mat_Cost_Total', 'Lab_Cost_Total', 'Line_Total']
ws_takeoff.append(headers_takeoff)

takeoff_data = [
    ['CON-001', 25, 0.05],
    ['CON-002', 500, 0.10],
    ['WOD-001', 350, 0.15],
    ['WOD-002', 80, 0.10],
    ['FIN-001', 120, 0.10],
    ['FIN-002', 15, 0.00],
    ['ELE-001', 1000, 0.05]
]

for row in takeoff_data:
    ws_takeoff.append(row + [None]*6)

# Format takeoff headers
takeoff_fill = PatternFill(start_color='9BBB59', end_color='9BBB59', fill_type='solid')
for cell in ws_takeoff[1]:
    cell.font = header_font
    cell.fill = takeoff_fill

for row in ws_takeoff.iter_rows(min_row=2, max_row=ws_takeoff.max_row, min_col=3, max_col=3):
    for cell in row:
        cell.number_format = '0%'

ws_takeoff.column_dimensions['A'].width = 12
ws_takeoff.column_dimensions['B'].width = 15
ws_takeoff.column_dimensions['C'].width = 18
ws_takeoff.column_dimensions['D'].width = 25
ws_takeoff.column_dimensions['E'].width = 25
ws_takeoff.column_dimensions['F'].width = 18
ws_takeoff.column_dimensions['G'].width = 18
ws_takeoff.column_dimensions['H'].width = 18
ws_takeoff.column_dimensions['I'].width = 18

wb.save('/home/ga/Documents/residential_takeoff.xlsx')
PYEOF

chown ga:ga "$TAKEOFF_FILE" 2>/dev/null || true

# Start WPS Spreadsheet with the file
su - ga -c "DISPLAY=:1 et '$TAKEOFF_FILE' &"
sleep 5

# Ensure maximized
DISPLAY=:1 wmctrl -r "WPS Spreadsheets" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -r "residential_takeoff" -b add,maximized_vert,maximized_horz 2>/dev/null || true

echo "Capturing initial state..."
sleep 2
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="