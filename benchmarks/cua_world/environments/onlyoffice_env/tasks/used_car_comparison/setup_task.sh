#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Used Car Comparison Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet as starting point
SHEET_PATH="$WORKSPACE_DIR/car_comparison.xlsx"

cat > /tmp/create_blank_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Sheet1"

# Create completely blank spreadsheet - agent will add all content
wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_blank_sheet.py
python3 /tmp/create_blank_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the blank spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_car_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_car_task.log || true
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

echo "=== Used Car Comparison Task Setup Complete ==="
echo ""
echo "📝 Scenario: You're helping a friend who needs to buy a used car within"
echo "   the next 3 days. They've shortlisted 4 vehicles but are overwhelmed."
echo "   Create a comparison spreadsheet to make a quick, informed decision."
echo ""
echo "Instructions:"
echo "  1. Create headers in Row 1: Vehicle, Year, Mileage, Price, Cost_Per_Mile, Notes"
echo "  2. Enter data for 4 vehicles in rows 2-5:"
echo "     Row 2: 2015 Honda Civic, 67000 miles, \$12500, 'Clean history, highway miles'"
echo "     Row 3: 2014 Toyota Corolla, 89000 miles, \$10200, 'One owner, recent timing belt'"
echo "     Row 4: 2016 Mazda3, 54000 miles, \$13800, 'Dent in rear bumper, good tires'"
echo "     Row 5: 2013 Ford Focus, 103000 miles, \$8900, 'Needs brake work soon'"
echo "  3. In Cost_Per_Mile column (E2:E5), create formula: =D2/(150000-C2)"
echo "     (This calculates cost per remaining mile assuming 150k total lifespan)"
echo "  4. Copy formula down for all 4 vehicles"
echo "  5. Add notes in column F for each vehicle"
echo "  6. Save the file (Ctrl+S) - it should save as car_comparison.xlsx"
echo ""