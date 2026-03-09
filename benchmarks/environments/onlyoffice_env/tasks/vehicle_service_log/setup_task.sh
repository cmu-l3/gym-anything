#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Vehicle Service Log Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with structure
SHEET_PATH="$WORKSPACE_DIR/vehicle_maintenance.xlsx"

cat > /tmp/create_vehicle_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment, PatternFill
import sys

wb = Workbook()
ws = wb.active
ws.title = "MaintenanceLog"

# Add column headers (Row 1)
headers = ["Service Date", "Odometer Reading", "Service Type", "Service Cost", "Next Service Mileage", "Next Service Date"]
for col, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add placeholder instructions in rows 2-6 (where data should go)
ws['A2'] = "[Enter date: 2024-06-15]"
ws['B2'] = "[Mileage: 35000]"
ws['C2'] = "[Service Type: Oil Change]"
ws['D2'] = "[Cost: $45.00]"

# Add summary section labels (rows 8-11)
ws['A8'] = "Total Maintenance Cost:"
ws['A8'].font = Font(bold=True)
ws['B8'] = "[Add SUM formula here]"

ws['A9'] = "Average Cost per Service:"
ws['A9'].font = Font(bold=True)
ws['B9'] = "[Add AVERAGE formula here]"

ws['A10'] = "Total Miles Driven:"
ws['A10'].font = Font(bold=True)
ws['B10'] = "[Calculate: latest - earliest mileage]"

ws['A11'] = "Cost per 1,000 Miles:"
ws['A11'].font = Font(bold=True)
ws['B11'] = "[Formula: (Total Cost / Total Miles) * 1000]"

# Add Next Service Alert section (rows 13-14)
ws['A13'] = "NEXT OIL CHANGE DUE:"
ws['A13'].font = Font(bold=True)
ws['A13'].fill = PatternFill(start_color="FFFF00", end_color="FFFF00", fill_type="solid")

ws['B13'] = "50,500 miles"
ws['B13'].fill = PatternFill(start_color="FFFF00", end_color="FFFF00", fill_type="solid")

ws['A14'] = "Days Until Due:"
ws['A14'].font = Font(bold=True)
ws['A14'].fill = PatternFill(start_color="FFFF00", end_color="FFFF00", fill_type="solid")

ws['B14'] = "[Formula: days between today and next service date]"
ws['B14'].fill = PatternFill(start_color="FFFF00", end_color="FFFF00", fill_type="solid")

# Set column widths
ws.column_dimensions['A'].width = 20
ws.column_dimensions['B'].width = 18
ws.column_dimensions['C'].width = 20
ws.column_dimensions['D'].width = 15
ws.column_dimensions['E'].width = 20
ws.column_dimensions['F'].width = 18

wb.save(sys.argv[1])
print(f"Vehicle maintenance spreadsheet template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_vehicle_sheet.py
python3 /tmp/create_vehicle_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Vehicle maintenance spreadsheet template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_vehicle_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_vehicle_task.log || true
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

echo "=== Vehicle Service Log Task Setup Complete ==="
echo ""
echo "📝 TASK: Create a vehicle maintenance tracking spreadsheet"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🚗 Vehicle: 2019 Toyota Camry (Current mileage: 47,500 miles)"
echo ""
echo "📋 Instructions:"
echo "  1. Enter 5 past maintenance records (rows 2-6) with the following data:"
echo ""
echo "     | Date       | Mileage | Service Type      | Cost     | Next Due    | Next Date  |"
echo "     |------------|---------|-------------------|----------|-------------|------------|"
echo "     | 2024-06-15 | 35000   | Oil Change        | \$45.00  | 40000       | 2024-12-15 |"
echo "     | 2024-07-20 | 36500   | Tire Rotation     | \$35.00  | 41500       | 2025-01-20 |"
echo "     | 2024-09-10 | 40200   | Oil Change        | \$48.00  | 45200       | 2025-03-10 |"
echo "     | 2024-10-30 | 42800   | Brake Inspection  | \$125.00 | 52800       | 2025-10-30 |"
echo "     | 2024-12-18 | 45500   | Oil Change        | \$47.00  | 50500       | 2025-06-18 |"
echo ""
echo "  2. Create summary formulas (rows 8-11):"
echo "     - B8: =SUM(D2:D6)        [Total cost]"
echo "     - B9: =AVERAGE(D2:D6)    [Average cost]"
echo "     - B10: =B6-B2            [Total miles: latest - earliest]"
echo "     - B11: =(B8/B10)*1000    [Cost per 1000 miles]"
echo ""
echo "  3. Update Next Service Alert (row 14):"
echo "     - B14: Calculate days until 2025-06-18 using TODAY() function"
echo ""
echo "  4. Apply formatting:"
echo "     - Column A (dates): Format as Date (MM/DD/YYYY)"
echo "     - Column D (costs): Format as Currency (\$ with 2 decimals)"
echo "     - Column B (mileage): Format with comma separators"
echo "     - Summary rows (8-11): Make labels bold"
echo "     - Alert section (13-14): Yellow background fill"
echo ""
echo "  5. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected totals:"
echo "  • Total Maintenance Cost: ~\$300"
echo "  • Average Cost per Service: ~\$60"
echo "  • Total Miles Driven: ~10,500"
echo "  • Cost per 1,000 Miles: ~\$28-29"
echo ""