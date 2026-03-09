#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Recipe Experiment Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create the initial spreadsheet with headers and instructions
SHEET_PATH="$WORKSPACE_DIR/bread_experiments.xlsx"

cat > /tmp/create_recipe_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Bread Experiments"

# Add header row with column titles
headers = [
    "Experiment Name",
    "Bread Flour (%)",
    "Whole Wheat (%)",
    "Rise Height (cm)",
    "Baking Time (min)",
    "Texture (1-5)",
    "Total Flour (g)"
]

for col_idx, header in enumerate(headers, start=1):
    cell = ws.cell(row=1, column=col_idx, value=header)
    cell.font = Font(bold=True)
    cell.alignment = Alignment(horizontal='center')

# Add instruction rows (these should be replaced by the agent)
ws['A2'] = "[Enter experiment name 1]"
ws['A3'] = "[Enter experiment name 2]"
ws['A4'] = "[Enter experiment name 3]"

# Add note in a separate cell
ws['A6'] = "Instructions:"
ws['A7'] = "1. Enter data for 3 bread experiments in rows 2-4"
ws['A8'] = "2. Classic White: 100% bread, 0% wheat, 12cm rise, 45min, texture 5"
ws['A9'] = "3. Rustic Blend: 70% bread, 30% wheat, 9cm rise, 50min, texture 4"
ws['A10'] = "4. Hearty Wheat: 50% bread, 50% wheat, 7cm rise, 55min, texture 3"
ws['A11'] = "5. Create formula in 'Total Flour (g)' column: (Bread % + Wheat %) * 5"

# Set column widths for readability
ws.column_dimensions['A'].width = 18
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 16
ws.column_dimensions['E'].width = 18
ws.column_dimensions['F'].width = 14
ws.column_dimensions['G'].width = 15

wb.save(sys.argv[1])
print(f"Recipe tracking spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_recipe_sheet.py
python3 /tmp/create_recipe_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_recipe_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_recipe_task.log || true
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

echo "=== Recipe Experiment Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Enter data for 3 bread baking experiments in rows 2-4"
echo "  2. Experiment 1 - Classic White:"
echo "     Name: Classic White, Bread Flour: 100, Whole Wheat: 0"
echo "     Rise: 12, Baking Time: 45, Texture: 5"
echo "  3. Experiment 2 - Rustic Blend:"
echo "     Name: Rustic Blend, Bread Flour: 70, Whole Wheat: 30"
echo "     Rise: 9, Baking Time: 50, Texture: 4"
echo "  4. Experiment 3 - Hearty Wheat:"
echo "     Name: Hearty Wheat, Bread Flour: 50, Whole Wheat: 50"
echo "     Rise: 7, Baking Time: 55, Texture: 3"
echo "  5. In column G (Total Flour), create formula: =(B2+C2)*5"
echo "     (Copy formula down for all 3 rows)"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected Total Flour values: 500g, 500g, 500g"