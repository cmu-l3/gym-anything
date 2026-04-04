#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Macro Nutrition Tracker Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Define the file path where user will save
SHEET_PATH="$WORKSPACE_DIR/macro_log.xlsx"

# Create a basic template spreadsheet with just headers to guide the user
cat > /tmp/create_macro_template.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Macro Log"

# Add column headers
ws['A1'] = "Food Item"
ws['B1'] = "Protein (g)"
ws['C1'] = "Carbs (g)"
ws['D1'] = "Fat (g)"

# Make headers bold
for cell in ['A1', 'B1', 'C1', 'D1']:
    ws[cell].font = Font(bold=True)
    ws[cell].alignment = Alignment(horizontal='center')

# Add some instructional text
ws['A2'] = "[Enter food items here]"
ws['B2'] = "[Enter protein]"
ws['C2'] = "[Enter carbs]"
ws['D2'] = "[Enter fat]"

# Adjust column widths for readability
ws.column_dimensions['A'].width = 25
ws.column_dimensions['B'].width = 15
ws.column_dimensions['C'].width = 15
ws.column_dimensions['D'].width = 15

wb.save(sys.argv[1])
print(f"Macro tracking template created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_macro_template.py
python3 /tmp/create_macro_template.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Macro tracking template created at: $SHEET_PATH"

# Launch ONLYOFFICE with the template spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_macro_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_macro_task.log || true
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

echo "=== Macro Nutrition Tracker Task Setup Complete ==="
echo "📝 Instructions:"
echo "  Create a macro tracking spreadsheet with:"
echo ""
echo "  Foods to log (yesterday's intake):"
echo "    - Greek yogurt (1 cup)"
echo "    - Banana (1 medium)"
echo "    - Granola (0.5 cup)"
echo "    - Grilled chicken breast (6 oz)"
echo "    - Brown rice (1 cup cooked)"
echo "    - Broccoli (1 cup)"
echo "    - Protein shake (1 scoop)"
echo "    - Almond butter (2 tbsp)"
echo "    - Salmon fillet (5 oz)"
echo "    - Sweet potato (1 medium)"
echo "    - Green beans (1 cup)"
echo ""
echo "  For each food, enter macros (protein, carbs, fat in grams)"
echo "  Add SUM formulas for totals"
echo "  Add target row: 150g protein, 200g carbs, 60g fat"
echo "  Add difference row: Total - Target"
echo "  Save with Ctrl+S"