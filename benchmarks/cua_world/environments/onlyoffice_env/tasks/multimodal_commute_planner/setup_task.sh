#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Multimodal Commute Planner Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet with task instructions
SHEET_PATH="$WORKSPACE_DIR/commute_comparison.xlsx"

cat > /tmp/create_commute_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
from openpyxl.styles import Font, Alignment
import sys

wb = Workbook()
ws = wb.active
ws.title = "Commute Comparison"

# Add instruction header
ws['A1'] = "TASK: Create a commute comparison to help decide which neighborhood to move to"
ws['A1'].font = Font(bold=True, size=12)

ws['A3'] = "Create a table with the following structure:"
ws['A4'] = "Headers: Neighborhood | Primary Method | Time (min) | Daily Cost | Monthly Cost | Backup Plan"

ws['A6'] = "Add data for three neighborhoods:"
ws['A7'] = "1. Riverside: Bike + Train, 45 min, $4.50 daily, backup: Bus + Train (55 min, $4.50)"
ws['A8'] = "2. Oakmont: Direct Bus, 38 min, $3.50 daily, backup: Rideshare (30 min, $18)"
ws['A9'] = "3. Downtown: Walk, 25 min, $0 daily, backup: Same (walk)"

ws['A11'] = "For Monthly Cost: Create formulas that calculate Daily Cost × 22 working days"
ws['A12'] = "Add a recommendation for the best option based on time and cost"

ws['A14'] = "Start your table below (or in a new sheet):"
ws['A15'] = "↓"

# Make the sheet a bit wider
ws.column_dimensions['A'].width = 80

wb.save(sys.argv[1])
print(f"Spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_commute_sheet.py
python3 /tmp/create_commute_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_commute_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_commute_task.log || true
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

echo "=== Multimodal Commute Planner Task Setup Complete ==="
echo "📝 Instructions:"
echo "  1. Create a table with headers: Neighborhood, Primary Method, Time (min), Daily Cost, Monthly Cost, Backup Plan"
echo "  2. Add three neighborhoods with their commute data:"
echo "     - Riverside: Bike+Train, 45 min, \$4.50 daily"
echo "     - Oakmont: Direct Bus, 38 min, \$3.50 daily"
echo "     - Downtown: Walk, 25 min, \$0 daily"
echo "  3. For Monthly Cost, use formulas: =Daily Cost × 22"
echo "  4. Add backup plans for each neighborhood"
echo "  5. Add a recommendation for best option"
echo "  6. Save the spreadsheet (Ctrl+S)"
echo ""
echo "Expected Monthly Costs:"
echo "  - Riverside: \$99 (4.50 × 22)"
echo "  - Oakmont: \$77 (3.50 × 22)"
echo "  - Downtown: \$0 (0 × 22)"