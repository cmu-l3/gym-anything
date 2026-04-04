#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Carbon Footprint Calculator Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with consumption data and conversion factors
SHEET_PATH="$WORKSPACE_DIR/carbon_footprint.xlsx"

cat > /tmp/create_carbon_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "Carbon Footprint"

# Set column widths for better visibility
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 20
ws.column_dimensions['E'].width = 20
ws.column_dimensions['F'].width = 20

# Header style
header_font = Font(bold=True, size=11)
header_fill = PatternFill(start_color="D3D3D3", end_color="D3D3D3", fill_type="solid")

# Add main data headers
ws['A1'] = "Category"
ws['A1'].font = header_font
ws['A1'].fill = header_fill

ws['B1'] = "Consumption"
ws['B1'].font = header_font
ws['B1'].fill = header_fill

ws['C1'] = "Emissions (kg CO2e)"
ws['C1'].font = header_font
ws['C1'].fill = header_fill

ws['D1'] = "Percentage of Total"
ws['D1'].font = header_font
ws['D1'].fill = header_fill

# Add consumption data
categories = [
    ("Electricity", "450 kWh"),
    ("Natural Gas", "35 therms"),
    ("Gasoline", "40 gallons"),
    ("Flight (short-haul)", "600 miles"),
    ("Food", "$400")
]

for i, (category, consumption) in enumerate(categories, start=2):
    ws[f'A{i}'] = category
    ws[f'B{i}'] = consumption

# Add total row (row 8, leaving row 7 blank)
ws['A8'] = "TOTAL"
ws['A8'].font = Font(bold=True, size=11)

# Add instructions/placeholders in formula columns
ws['C2'] = "[Create formula: =B_value * F_factor]"
ws['D2'] = "[Create formula: =C2/$C$8*100]"

# Add reference table for conversion factors
ws['E1'] = "Reference: CO2e Factors"
ws['E1'].font = header_font
ws['E1'].fill = header_fill

ws['F1'] = "kg CO2e per unit"
ws['F1'].font = header_font
ws['F1'].fill = header_fill

conversion_factors = [
    ("Electricity (kWh)", 0.5),
    ("Natural Gas (therm)", 5.3),
    ("Gasoline (gallon)", 8.9),
    ("Flight (mile)", 0.24),
    ("Food ($)", 2.5)
]

for i, (source, factor) in enumerate(conversion_factors, start=2):
    ws[f'E{i}'] = source
    ws[f'F{i}'] = factor

# Add instructions at the bottom
ws['A10'] = "Instructions:"
ws['A10'].font = Font(bold=True)
ws['A11'] = "1. In C2:C6, create formulas multiplying consumption by conversion factors"
ws['A12'] = "2. In C8, create SUM formula for total emissions"
ws['A13'] = "3. In D2:D6, create percentage formulas (use $C$8 for absolute reference)"
ws['A14'] = "4. Save the file (Ctrl+S)"

wb.save(sys.argv[1])
print(f"Carbon footprint spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_carbon_sheet.py
python3 /tmp/create_carbon_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_carbon_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_carbon_task.log || true
fi

# Wait for window
if ! wait_for_window "ONLYOFFICE" 30; then
    echo "ERROR: ONLYOFFICE window did not appear"
fi

# Protect ONLYOFFICE from OOM killer
protect_onlyoffice_from_oom

# Click center to focus correct desktop
su - ga -c "DISPLAY=:1 xdotool mousemove 600 600 click 1" || true
sleep 1

# Focus ONLYOFFICE window
focus_onlyoffice_window

echo "=== Carbon Footprint Calculator Task Setup Complete ==="
echo "📝 Task Overview:"
echo "  Calculate your personal carbon footprint from household data"
echo ""
echo "📋 Instructions:"
echo "  1. In cell C2, create formula: =B2*F2 (450 kWh × 0.5 kg/kWh)"
echo "  2. Copy this formula down to C3:C6 (adjust row numbers)"
echo "  3. In cell C8, create formula: =SUM(C2:C6)"
echo "  4. In cell D2, create formula: =C2/\$C\$8*100"
echo "  5. Copy this formula down to D3:D6"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected results:"
echo "  - Electricity: ~225 kg CO2e (12%)"
echo "  - Natural Gas: ~185.5 kg CO2e (10%)"
echo "  - Gasoline: ~356 kg CO2e (19%)"
echo "  - Flight: ~144 kg CO2e (8%)"
echo "  - Food: ~1000 kg CO2e (52%)"
echo "  - TOTAL: ~1910.5 kg CO2e"