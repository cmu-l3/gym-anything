#!/bin/bash
echo "=== Setting up GHG Emissions task ==="

# Record task start time
date +%s > /tmp/task_start_time.txt

# Generate realistic data file using python and openpyxl
python3 << 'PYEOF'
import openpyxl
from openpyxl import Workbook
from openpyxl.styles import Font, PatternFill

wb = Workbook()
ws_factors = wb.active
ws_factors.title = 'Emission_Factors'

# EPA Emission Factors Data
headers_factors = ['Source_Type', 'Unit', 'CO2_Factor_kg_per_unit', 'CH4_Factor_g_per_unit', 'N2O_Factor_g_per_unit', '', '', 'Gas', 'GWP']
ws_factors.append(headers_factors)
ws_factors.append(['Electricity', 'kWh', 0.386, 0.030, 0.004, '', '', 'CO2', 1])
ws_factors.append(['Natural Gas', 'therms', 5.300, 0.500, 0.010, '', '', 'CH4', 25])
ws_factors.append(['Gasoline', 'gallons', 8.780, 0.380, 0.080, '', '', 'N2O', 298])

# Format factors headers
header_font = Font(bold=True)
header_fill = PatternFill(start_color='E2EFDA', end_color='E2EFDA', fill_type='solid')
for cell in ws_factors[1]:
    cell.font = header_font
    cell.fill = header_fill

ws_factors.column_dimensions['A'].width = 15
ws_factors.column_dimensions['C'].width = 25
ws_factors.column_dimensions['D'].width = 25
ws_factors.column_dimensions['E'].width = 25

ws_data = wb.create_sheet('Energy_Data')
headers_data = ['Month', 'Facility', 'Source_Type', 'Scope', 'Consumption', 'Unit', 'CO2_kg', 'CH4_kg', 'N2O_kg', 'CO2e_kg', 'MT_CO2e']
ws_data.append(headers_data)

for cell in ws_data[1]:
    cell.font = header_font
    cell.fill = header_fill

# Realistic 3-month consumption data profile for campus buildings
data_rows = [
    ['Jan', 'Science Building', 'Electricity', 'Scope 2', 145000, 'kWh'],
    ['Jan', 'Science Building', 'Natural Gas', 'Scope 1', 6500, 'therms'],
    ['Jan', 'Library', 'Electricity', 'Scope 2', 85000, 'kWh'],
    ['Jan', 'Library', 'Natural Gas', 'Scope 1', 3200, 'therms'],
    ['Jan', 'Dorms', 'Electricity', 'Scope 2', 210000, 'kWh'],
    ['Jan', 'Dorms', 'Natural Gas', 'Scope 1', 8500, 'therms'],
    ['Jan', 'Admin', 'Electricity', 'Scope 2', 65000, 'kWh'],
    ['Jan', 'Admin', 'Natural Gas', 'Scope 1', 2100, 'therms'],
    ['Jan', 'Fleet', 'Gasoline', 'Scope 1', 1200, 'gallons'],
    ['Feb', 'Science Building', 'Electricity', 'Scope 2', 142000, 'kWh'],
    ['Feb', 'Science Building', 'Natural Gas', 'Scope 1', 6100, 'therms'],
    ['Feb', 'Library', 'Electricity', 'Scope 2', 83000, 'kWh'],
    ['Feb', 'Library', 'Natural Gas', 'Scope 1', 3000, 'therms'],
    ['Feb', 'Dorms', 'Electricity', 'Scope 2', 205000, 'kWh'],
    ['Feb', 'Dorms', 'Natural Gas', 'Scope 1', 8100, 'therms'],
    ['Feb', 'Admin', 'Electricity', 'Scope 2', 63000, 'kWh'],
    ['Feb', 'Admin', 'Natural Gas', 'Scope 1', 1900, 'therms'],
    ['Feb', 'Fleet', 'Gasoline', 'Scope 1', 1150, 'gallons'],
    ['Mar', 'Science Building', 'Electricity', 'Scope 2', 138000, 'kWh'],
    ['Mar', 'Science Building', 'Natural Gas', 'Scope 1', 4500, 'therms'],
    ['Mar', 'Library', 'Electricity', 'Scope 2', 80000, 'kWh'],
    ['Mar', 'Library', 'Natural Gas', 'Scope 1', 2100, 'therms'],
    ['Mar', 'Dorms', 'Electricity', 'Scope 2', 190000, 'kWh'],
    ['Mar', 'Dorms', 'Natural Gas', 'Scope 1', 5000, 'therms'],
    ['Mar', 'Admin', 'Electricity', 'Scope 2', 60000, 'kWh'],
    ['Mar', 'Admin', 'Natural Gas', 'Scope 1', 1200, 'therms'],
    ['Mar', 'Fleet', 'Gasoline', 'Scope 1', 1300, 'gallons']
]

for row in data_rows:
    ws_data.append(row)

ws_data.column_dimensions['A'].width = 10
ws_data.column_dimensions['B'].width = 20
ws_data.column_dimensions['C'].width = 15
ws_data.column_dimensions['D'].width = 10
ws_data.column_dimensions['E'].width = 12
ws_data.column_dimensions['F'].width = 10
for col in ['G', 'H', 'I', 'J', 'K']:
    ws_data.column_dimensions[col].width = 12

wb.save('/home/ga/Documents/ghg_inventory_2024.xlsx')
print("Successfully generated ghg_inventory_2024.xlsx")
PYEOF

chown ga:ga /home/ga/Documents/ghg_inventory_2024.xlsx

# Ensure WPS Spreadsheet is running and file is opened
if ! pgrep -f "et" > /dev/null; then
    su - ga -c "DISPLAY=:1 et /home/ga/Documents/ghg_inventory_2024.xlsx &"
    sleep 5
fi

# Wait for window to appear and maximize
for i in {1..30}; do
    if DISPLAY=:1 wmctrl -l | grep -i "ghg_inventory_2024"; then
        break
    fi
    sleep 1
done

DISPLAY=:1 wmctrl -r "ghg_inventory" -b add,maximized_vert,maximized_horz 2>/dev/null || true
DISPLAY=:1 wmctrl -a "ghg_inventory" 2>/dev/null || true

# Take initial screenshot for evidence
DISPLAY=:1 scrot /tmp/task_initial.png 2>/dev/null || true

echo "=== Task setup complete ==="