#!/bin/bash
# set -euo pipefail

source /workspace/scripts/task_utils.sh

echo "=== Setting up Water Meter Detective Task ==="

# Clean up temporary files from previous tasks
cleanup_temp_files

# Kill any existing ONLYOFFICE instances
kill_onlyoffice ga
sleep 1

# Create workspace directory
WORKSPACE_DIR="/home/ga/Documents/Spreadsheets"
sudo -u ga mkdir -p "$WORKSPACE_DIR"

# Create a blank spreadsheet file
SHEET_PATH="$WORKSPACE_DIR/water_meter_tracking.xlsx"

cat > /tmp/create_water_sheet.py << 'PYEOF'
#!/usr/bin/env python3
from openpyxl import Workbook
import sys

wb = Workbook()
ws = wb.active
ws.title = "Meter Tracking"

# Create a completely blank sheet - user will create everything
# This makes the task realistic (starting from scratch like a real homeowner would)

wb.save(sys.argv[1])
print(f"Blank spreadsheet created: {sys.argv[1]}")
PYEOF

chmod +x /tmp/create_water_sheet.py
python3 /tmp/create_water_sheet.py "$SHEET_PATH"
chown ga:ga "$SHEET_PATH"

echo "✅ Blank spreadsheet created at: $SHEET_PATH"

# Launch ONLYOFFICE with the spreadsheet
echo "Launching ONLYOFFICE Spreadsheet Editor..."
su - ga -c "DISPLAY=:1 onlyoffice-desktopeditors '$SHEET_PATH' > /tmp/onlyoffice_water_task.log 2>&1 &"

# Wait for ONLYOFFICE to start
if ! wait_for_process "onlyoffice-desktopeditors" 20; then
    echo "ERROR: ONLYOFFICE failed to start"
    cat /tmp/onlyoffice_water_task.log || true
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

echo "=== Water Meter Detective Task Setup Complete ==="
echo ""
echo "🚨 SCENARIO: Your water bill shows 12,500 gallons used last month"
echo "   (normally 4,500 gallons). You suspect a leak but can't find it."
echo "   Before calling a plumber (\$150 service call), systematically"
echo "   track your water meter to identify the source."
echo ""
echo "📊 CREATE A TRACKING SPREADSHEET WITH:"
echo ""
echo "  ROW 1 - Headers:"
echo "    • Date | Time | Meter Reading (gallons) | Usage Since Last"
echo "    • Hours Elapsed | Gallons/Hour Rate | Testing Notes"
echo ""
echo "  ROWS 2-8 - Seven meter readings (example data):"
echo "    • 5/15/2024 7:00 AM,  845230, [first reading]"
echo "    • 5/15/2024 7:00 PM,  845638, [calculate: 845638-845230=408]"
echo "    • 5/16/2024 7:00 AM,  846102, [calculate differences]"
echo "    • 5/16/2024 7:00 PM,  846520, Note: 'Guest toilet isolated'"
echo "    • 5/17/2024 7:00 AM,  846750, Note: 'Guest toilet isolated'"
echo "    • 5/18/2024 7:00 AM,  847190, Note: 'Back to normal'"
echo "    • 5/19/2024 7:00 AM,  847650"
echo ""
echo "  FORMULAS NEEDED:"
echo "    • Column D (Usage): =C3-C2 (current - previous reading)"
echo "    • Column F (Rate): =D3/E3 (usage / hours elapsed)"
echo ""
echo "  ROWS 10-15 - Summary section:"
echo "    • Total gallons tracked, average daily usage"
echo "    • Key finding: Usage ~38 gal/hr → ~19 gal/hr when toilet isolated"
echo "    • Conclusion: Guest bathroom toilet has slow leak (~230 gal/day)"
echo ""
echo "💾 Save with Ctrl+S when complete."
echo ""