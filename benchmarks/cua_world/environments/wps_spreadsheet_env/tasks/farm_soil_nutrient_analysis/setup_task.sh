#!/bin/bash
echo "=== Setting up farm_soil_nutrient_analysis task ==="

SOIL_FILE="/home/ga/Documents/soil_test_results.xlsx"

rm -f "$SOIL_FILE" 2>/dev/null || true

# Create soil test results spreadsheet
python3 << 'PYEOF'
import random
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill, Alignment

wb = Workbook()
ws_soil = wb.active
ws_soil.title = 'Soil_Data'

ws_targets = wb.create_sheet(title='Crop_Targets')

# Crop Targets
targets = [
    ['Crop', 'Target_N_ppm', 'Target_P_ppm', 'Target_K_ppm'],
    ['Corn', 150, 45, 120],
    ['Soybeans', 40, 35, 100],
    ['Wheat', 100, 40, 90],
    ['Cotton', 120, 30, 110]
]

for row in targets:
    ws_targets.append(row)

header_font = Font(bold=True)
header_fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')

for cell in ws_targets[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

# Soil Data
headers = ['Grid_ID', 'Acres', 'Planned_Crop', 'pH_Level', 'N_ppm', 'P_ppm', 'K_ppm']
ws_soil.append(headers)

crops = ['Corn', 'Soybeans', 'Wheat', 'Cotton']
random.seed(42) # Deterministic data for verification stability

for i in range(1, 251):
    grid_id = f"G{i:03d}"
    acres = round(random.uniform(2.5, 10.0), 1)
    crop = random.choice(crops)
    ph = round(random.uniform(4.5, 8.0), 1)
    n = random.randint(20, 160)
    p = random.randint(10, 60)
    k = random.randint(50, 150)
    
    ws_soil.append([grid_id, acres, crop, ph, n, p, k])

for cell in ws_soil[1]:
    cell.font = header_font
    cell.fill = header_fill
    cell.alignment = Alignment(horizontal='center')

ws_soil.column_dimensions['A'].width = 10
ws_soil.column_dimensions['B'].width = 10
ws_soil.column_dimensions['C'].width = 15
ws_soil.column_dimensions['D'].width = 10
ws_soil.column_dimensions['E'].width = 10
ws_soil.column_dimensions['F'].width = 10
ws_soil.column_dimensions['G'].width = 10

wb.save('/home/ga/Documents/soil_test_results.xlsx')
print(f"Created soil test results file with 250 grid records.")

PYEOF

chown ga:ga "$SOIL_FILE" 2>/dev/null || true

# Record initial file modification time to prevent gaming
INITIAL_MTIME=$(stat -c %Y "$SOIL_FILE" 2>/dev/null || echo "0")
echo "$INITIAL_MTIME" > /tmp/initial_mtime.txt
date +%s > /tmp/task_start_time.txt

# Launch WPS Spreadsheet with the soil test file
source /workspace/scripts/launch_wps_for_task.sh
launch_wps_with_file "$SOIL_FILE"

echo "=== Task setup complete ==="